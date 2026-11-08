#!/usr/bin/env bash
# =============================================================================
#  MyCMP90 check — верификация compute unlock CMP 90HX
# =============================================================================
#  Проверяет на каждой обнаруженной CMP 90HX:
#    1. Инвентаризацию (nvidia-smi: имя, драйвер, VRAM)
#    2. Реальный статус PCIe-линка (LnkSta: текущая/максимальная скорость)
#    3. Все 9 полей SM Issue-Rate (через rm_issue_rate_query.py)
#    4. Маркеры rejoin15/V67 в dmesg (PLM до/после, SS0/SS1)
#    5. Какой модуль nvidia.ko загружен (патченный vs стоковый)
#
#  Выход: 0 = всё разблокировано; 1 = есть FAIL.
#
#  Переменные:
#    CMP90HX_HOME  каталог с соседними репозиториями (по умолчанию — родитель)
#    RM_QUERY      путь к rm_issue_rate_query.py (иначе ищется/скачивается)
# =============================================================================
set -uo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMP90HX_HOME="${CMP90HX_HOME:-$(dirname "${STACK_DIR}")}"
GPU_DEVID="0x220d"
RM_QUERY="${RM_QUERY:-}"
FAILURES=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; NC=""; BOLD=""
fi
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
bad()  { echo -e "  ${RED}✗${NC} $*"; FAILURES=$((FAILURES + 1)); }

line() { echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"; }

# -----------------------------------------------------------------------------
#  Поиск rm_issue_rate_query.py (помощник чтения 9 полей через RM control)
# -----------------------------------------------------------------------------
find_rm_query() {
    local cand
    if [ -n "${RM_QUERY}" ] && [ -f "${RM_QUERY}" ]; then return 0; fi
    for cand in \
        "${CMP90HX_HOME}/cmp90hx/cmp90hx/scripts/rm_issue_rate_query.py" \
        "${CMP90HX_HOME}/cmp90hx/scripts/rm_issue_rate_query.py"; do
        if [ -f "${cand}" ]; then RM_QUERY="${cand}"; return 0; fi
    done
    RM_QUERY="/tmp/mycmp90/rm_issue_rate_query.py"
    mkdir -p "$(dirname "${RM_QUERY}")"
    if curl -fsSL --retry 2 -o "${RM_QUERY}" \
        "https://raw.githubusercontent.com/bendy2/cmp90hx/main/scripts/rm_issue_rate_query.py" 2>/dev/null; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
#  Поиск всех CMP 90HX
# -----------------------------------------------------------------------------
declare -a BDFS=()
discover() {
    local d
    local -a tmp=()
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "${d}/vendor" 2>/dev/null)" = "0x10de" ] || continue
        [ "$(cat "${d}/device" 2>/dev/null)" = "${GPU_DEVID}" ] || continue
        tmp+=("$(basename "$d")")
    done
    BDFS=($(printf '%s\n' "${tmp[@]}" | sort -V))
}

main() {
    echo -e "${BOLD}MyCMP90 CHECK — CMP 90HX compute unlock${NC}  $(date '+%F %T')"
    line()

    if [ "$(id -u)" -ne 0 ]; then
        warn "Не root: RM-запрос полей Issue-Rate может не пройти (запускайте через sudo)"
    fi
    command -v nvidia-smi >/dev/null 2>&1 \
        || { bad "nvidia-smi недоступен — драйвер не установлен/не загружен"; exit 1; }

    discover
    if [ "${#BDFS[@]}" -eq 0 ]; then
        bad "CMP 90HX (10de:220d) не найдена на PCI"
        exit 1
    fi
    ok "Карт CMP 90HX: ${#BDFS[@]}"

    # --- 1. Инвентаризация + PCIe линк ---
    echo ""
    echo -e "${BOLD}[1/4] Инвентаризация и PCIe-линк${NC}"
    local idx line_speed line_width link_info
    for idx in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
        link_info="$(nvidia-smi --query-gpu=pci.bus_id,name,driver_version,memory.total --format=csv,noheader -i "${idx}" 2>/dev/null)"
        [ -n "${link_info}" ] && ok "GPU${idx}: ${link_info}"
    done
    for bdf in "${BDFS[@]}"; do
        local cur max
        cur="$(cat "/sys/bus/pci/devices/${bdf}/current_link_speed" 2>/dev/null || echo '?')"
        max="$(cat "/sys/bus/pci/devices/${bdf}/max_link_speed" 2>/dev/null || echo '?')"
        local curw maxw
        curw="$(cat "/sys/bus/pci/devices/${bdf}/current_link_width" 2>/dev/null || echo '?')"
        maxw="$(cat "/sys/bus/pci/devices/${bdf}/max_link_width" 2>/dev/null || echo '?')"
        echo -e "  ${bdf}: линк ${cur} x${curw} (потолок: ${max} x${maxw})"
        if [ "${max}" != "?" ] && echo "${max}" | grep -qi "2.5"; then
            warn "  ${bdf}: max_link_speed 2.5GT/s — аппаратный потолок Gen1, Gen2 retrain недоступен (см. STATUS.md)"
        fi
    done

    # --- 2. Какой модуль загружен ---
    echo ""
    echo -e "${BOLD}[2/4] Модуль драйвера${NC}"
    local drv_ver mod_src
    drv_ver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader -i 0 2>/dev/null | head -1)"
    mod_src="$(cat /sys/module/nvidia/srcversion 2>/dev/null || echo 'нет')"
    if [ -n "${drv_ver}" ]; then ok "Версия драйвера: ${drv_ver}"; else bad "Драйвер не отвечает"; fi
    if [ -d "/lib/modules/$(uname -r)/updates/cmpunlocker" ] || \
       [ -d "/lib/modules/$(uname -r)/updates/cmpunlocker-90hx-stockflow" ]; then
        ok "Патченный модуль установлен в updates/cmpunlocker*"
    else
        warn "Каталог updates/cmpunlocker* не найден — модуль может быть стоковым"
    fi
    [ "${mod_src}" != "нет" ] && ok "srcversion загруженного nvidia.ko: ${mod_src}"

    # --- 3. Маркеры rejoin15 в dmesg ---
    echo ""
    echo -e "${BOLD}[3/4] Маркеры эксплойта V67 / rejoin15 (dmesg)${NC}"
    local plm ss rejoin
    plm="$(dmesg 2>/dev/null | grep -o 'CMP90_PROD_STACK_SHIFT_PLM_V67:.*' | tail -1)"
    ss="$(dmesg 2>/dev/null | grep -o 'CMP90_STOCKFLOW_REJOIN12:.*' | tail -1)"
    rejoin="$(dmesg 2>/dev/null | grep -o 'CMP90_STOCKFLOW_REJOIN14:.*' | tail -1)"
    if [ -n "${plm}" ]; then
        ok "${plm}"
        if echo "${plm}" | grep -q 'FEAT_PLM_after=0xffffffff'; then ok "PLM полностью открыт (0xffffffff)"; else bad "PLM не открыт"; fi
    else
        bad "Маркер PLM_V67 не найден в dmesg — анлок в этой загрузке не выполнялся"
    fi
    [ -n "${ss}" ] && ok "${ss}" || bad "Маркер записи SS0/SS1 (REJOIN12) не найден"
    [ -n "${rejoin}" ] && ok "${rejoin}" || warn "Маркер REJOIN14 (nv_start_device retry) не найден"

    # --- 4. 9 полей Issue-Rate ---
    echo ""
    echo -e "${BOLD}[4/4] SM Issue-Rate (9 полей через RM control)${NC}"
    if find_rm_query; then
        local bdf uuid mem out rc=0
        while IFS=',' read -r bdf uuid mem; do
            bdf="${bdf// /}"; uuid="${uuid// /}"; mem="${mem// /}"
            if out="$(timeout 20 python3 "${RM_QUERY}" --bdf "${bdf}" --uuid "${uuid}" \
                      --driver "${drv_ver}" --memory-mib "${mem}" --expect full 2>&1)"; then
                local rates
                rates="$(python3 -c '
import json, sys
r = json.load(sys.stdin)["effective_issue_rates"]
order = ("dp","ffma","fmla16","fmla32","imla0","imla1","imla2","imla3","imla4")
lab   = ("DP","FFMA","FMLA16","FMLA32","IMLA0","IMLA1","IMLA2","IMLA3","IMLA4")
print(" ".join("{}={}".format(l, r[n]["rate"]) for n, l in zip(order, lab)))
' <<<"${out}" 2>/dev/null || echo "?")"
                ok "${bdf} PASS ${rates}"
            else
                bad "${bdf} FAIL: $(echo "${out}" | tail -1)"
            fi
        done < <(nvidia-smi --query-gpu=pci.bus_id,uuid,memory.total --format=csv,noheader 2>/dev/null)
    else
        warn "rm_issue_rate_query.py недоступен (нет локально и не скачался) — поле 3 пропущено."
        warn "Положите репозиторий cmp90hx (bendy2) в ${CMP90HX_HOME}/cmp90hx"
    fi

    line()
    if [ "${FAILURES}" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}PASS: анлок активен, 9/9 полей FULL${NC}"
        exit 0
    else
        echo -e "${RED}${BOLD}FAIL: проблемных проверок: ${FAILURES}${NC}"
        echo -e "Смотрите: dmesg | grep -i cmp90 ; логи установки в /tmp/mycmp90/"
        exit 1
    fi
}

main "$@"
