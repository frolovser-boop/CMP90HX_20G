#!/usr/bin/env bash
# =============================================================================
#  agent-status.sh — полный отчёт о состоянии сервера/карт CMP 90HX.
#  Рассчитан на чтение ИИ-агентом: устойчивые секции `## NAME` и строки KEY: val.
#  Запуск:  sudo ./agent-status.sh        (без root — часть данных будет недоступна)
#  Результат печатается в stdout; с --save ещё и в /opt/mycmp90/logs/status-<ts>.log
# =============================================================================
set -uo pipefail
SAVE=0; [ "${1:-}" = "--save" ] && SAVE=1
TS="$(date '+%F %T')"

emit() { printf '%s\n' "$*"; }
section() { emit ""; emit "## $*"; }

# Сохраняемая копия (только при --save)
if [ "${SAVE}" -eq 1 ]; then
    mkdir -p /opt/mycmp90/logs
    OUT="/opt/mycmp90/logs/status-$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee "${OUT}") 2>&1
fi

section HOST
emit "TIME: ${TS}"
emit "HOSTNAME: $(hostname)"
emit "KERNEL: $(uname -r)"
emit "UPTIME: $(uptime -p 2>/dev/null || uptime)"
emit "DISK_ROOT: $(df -h / | awk 'NR==2{print $3"/"$2" used "$5}')"
[ -f /etc/os-release ] && emit "OS: $(. /etc/os-release && echo "${PRETTY_NAME}")"

section GPU_INVENTORY
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,name,pci.bus_id,driver_version,memory.total,temperature.gpu,power.draw,power.limit,clocks.sm --format=csv,noheader 2>/dev/null | \
        while IFS=, read -r idx name bus drv mem temp pdraw plimit sm; do
            emit "GPU${idx// /}: ${name// /} bus=${bus// /} driver=${drv// /} vram=${mem// /}MiB temp=${temp// /}C power=${pdraw// /}/${plimit// /}W sm=${sm// /}MHz"
        done
    NVIDIA_GPUS=$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | wc -l)
    emit "GPU_COUNT: ${NVIDIA_GPUS}"
else
    emit "NVIDIA_SMI: ABSENT (драйвер не установлен/не загружен)"
fi

section PCI_CMP90
CMP90=0
for d in /sys/bus/pci/devices/*; do
    [ "$(cat "${d}/vendor" 2>/dev/null)" = "0x10de" ] || continue
    [ "$(cat "${d}/device" 2>/dev/null)" = "0x220d" ] || continue
    bdf=$(basename "$d")
    CMP90=$((CMP90+1))
    cur=$(cat "${d}/current_link_speed" 2>/dev/null || echo '?')
    max=$(cat "${d}/max_link_speed" 2>/dev/null || echo '?')
    curw=$(cat "${d}/current_link_width" 2>/dev/null || echo '?')
    emit "CMP90: bdf=${bdf} link=${cur} x${curw} (max ${max})"
done
emit "CMP90_COUNT: ${CMP90}"

section DRIVER_MODULE
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    emit "DRIVER_VERSION: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader -i 0 2>/dev/null | head -1)"
fi
emit "MODULE_SRCVERSION: $(cat /sys/module/nvidia/srcversion 2>/dev/null || echo N/A)"
[ -d "/lib/modules/$(uname -r)/updates/cmpunlocker" ] && emit "PATCHED_MODULE: updates/cmpunlocker присутствует"
[ -d "/lib/modules/$(uname -r)/updates/cmpunlocker-90hx-stockflow" ] && emit "PATCHED_MODULE: updates/cmpunlocker-90hx-stockflow присутствует"

section UNLOCK_STATUS
STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="/opt/mycmp90/stack/check.sh"
[ -f "${CHECK}" ] || CHECK="${STACK_DIR}/check.sh"
[ -f "${CHECK}" ] || CHECK="../3_linux_server/check.sh"
if [ -f "${CHECK}" ]; then
    OUT_CHECK="$(timeout 120 bash "${CHECK}" 2>&1)"; RC=$?
    emit "CHECK_RC: ${RC}"
    echo "${OUT_CHECK}" | grep -E "PASS|FAIL|✓|✗|линк|LnkSta" | head -30
    echo "${OUT_CHECK}" | grep -q "PASS: анлок активен" && emit "UNLOCK: PASS" || emit "UNLOCK: FAIL_OR_UNKNOWN"
else
    emit "UNLOCK: UNKNOWN (check.sh не найден — установите стек, см. 3_linux_server)"
fi
DM=$(dmesg 2>/dev/null | grep -E "CMP90_PROD_STACK_SHIFT_PLM_V67|CMP90_STOCKFLOW_REJOIN" | tail -4)
if [ -n "${DM}" ]; then
    echo "${DM}" | while read -r l; do emit "DMESG: ${l#\[ *[0-9.]*\] }"; done
else
    emit "DMESG: маркеры rejoin15/V67 не найдены (анлок в этой загрузке не выполнялся или dmesg недоступен)"
fi

section THERMAL_POWER
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,temperature.gpu,power.draw,power.limit,fan.speed --format=csv,noheader 2>/dev/null | \
        while IFS=, read -r idx t pd pl f; do emit "THERM: GPU${idx// /} ${t// /}C ${pd// /}/${pl// /}W fan=${f// /}"; done
fi

section P2P
if command -v nvidia-smi >/dev/null 2>&1 && [ "$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | wc -l)" -ge 2 ]; then
    R=$(nvidia-smi topo -p2p r 2>&1 | tail -n +2)
    emit "P2P_READ_MATRIX:"
    echo "${R}" | while read -r l; do emit "  ${l}"; done
    nvidia-smi topo -p2p r 2>/dev/null | grep -q "OK" && emit "P2P: OK" || emit "P2P: NOT_OK_OR_ABSENT (см. p2p-setup.sh)"
else
    emit "P2P: N/A (карт < 2)"
fi

section TOOLS
for p in /opt/mycmp90/tools/rm_issue_rate_query.py \
         /opt/mycmp90/stack/install-unlock.sh \
         /opt/mycmp90/cmp90hx-unlock/install.sh \
         /home/nvmt_3000_4090/nvmt; do
    [ -e "${p}" ] && emit "PRESENT: ${p}"
done
emit "LLAMA_BENCH: $(command -v llama-bench || echo absent)"
python3 -c 'import torch' 2>/dev/null && emit "PYTORCH: installed" || emit "PYTORCH: absent"
python3 -c 'import vllm' 2>/dev/null && emit "VLLM: installed" || emit "VLLM: absent"

section LOGS_DIR
ls -t /opt/mycmp90/logs/ 2>/dev/null | head -5 | while read -r f; do emit "RECENT: ${f}"; done

emit ""
emit "## END (agent-status: секции HOST/GPU_INVENTORY/PCI_CMP90/DRIVER_MODULE/UNLOCK_STATUS/THERMAL_POWER/P2P/TOOLS)"
exit 0
