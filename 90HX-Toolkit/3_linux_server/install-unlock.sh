#!/usr/bin/env bash
# =============================================================================
#  MyCMP90 stack installer — CMP 90HX Compute Unlock (rejoin15 / 610.43.03)
# =============================================================================
#  Оркестратор: ставит проверенный стек из cmp90hx-unlock на чистую машину
#  Ubuntu 20.04/22.04/24.04 или Debian 11/12.
#
#  Что делает:
#    1. Preflight: root, GPU 10de:220d, Secure Boot off, заголовки ядра,
#       nouveau.
#    2. Находит (или клонирует) репозиторий cmp90hx-unlock рядом с MyCMP90.
#    3. Ставит userspace 610.43.03 + GSP-прошивку, если их нет.
#    4. Запускает sudo ./install.sh --profile=cmp90-rejoin15
#       (эксплойт V67 инлайн в инициализацию драйвера, персистентно).
#    5. Запускает stack/check.sh и печатает следующие шаги.
#
#  Использование:
#    sudo ./install-unlock.sh                 # полная установка
#    sudo ./install-unlock.sh --preflight     # только проверка окружения
#
#  Переменные:
#    CMP90HX_HOME  каталог с соседними репозиториями
#                  (по умолчанию — родитель каталога, где лежит stack/)
# =============================================================================
set -uo pipefail

DRIVER_VERSION="610.43.03"
RUN_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
UNLOCK_REPO_URL="https://github.com/WildFlash1st/cmp90hx-unlock.git"
GPU_DEVID="0x220d"

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMP90HX_HOME="${CMP90HX_HOME:-$(dirname "${STACK_DIR}")}"
WORKDIR="${CMP90_UNLOCK_WORK:-/tmp/mycmp90}"
LOG_FILE="${WORKDIR}/install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${WORKDIR}"

# ---- вывод ------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; NC=""; BOLD=""
fi
step() { echo ""; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}${BOLD}$*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; echo -e "${YELLOW}Лог: ${LOG_FILE}${NC}" >&2; exit 1; }

# =============================================================================
#  Preflight
# =============================================================================
preflight() {
    step "Preflight — проверка окружения"

    [ "$(id -u)" -eq 0 ] || die "Запустите как root: sudo $0"

    # --- GPU ---
    local found=0 dev
    for dev in /sys/bus/pci/devices/*/device; do
        if [ "$(cat "$dev" 2>/dev/null)" = "${GPU_DEVID}" ]; then
            found=$((found + 1))
            ok "Найдена CMP 90HX: $(dirname "$dev" | xargs basename) ($(cat "$(dirname "$dev")/vendor"):$(cat "$dev"))"
        fi
    done
    [ "${found}" -gt 0 ] || die "GPU 10de:${GPU_DEVID} (CMP 90HX) не обнаружена. lspci -nn | grep -i nvidia"
    ok "Карт CMP 90HX: ${found}"

    # --- Secure Boot ---
    if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
        die "Secure Boot ВКЛЮЧЁН. Отключите в BIOS/UEFI и перезагрузитесь — патченный модуль не загрузится."
    fi
    ok "Secure Boot: отключён (или проверить нечем — продолжаем)"

    # --- ОС ---
    if [ -f /etc/os-release ]; then
        ok "ОС: $(. /etc/os-release && echo "${PRETTY_NAME}")"
    fi

    # --- Заголовки ядра и тулчейн ---
    local kver srcdir
    kver="$(uname -r)"
    srcdir="/lib/modules/${kver}/build"
    if [ ! -d "${srcdir}" ]; then
        warn "Заголовки ядра ${kver} не найдены — попробую поставить apt-пакеты"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y >>"${LOG_FILE}" 2>&1 \
                && apt-get install -y build-essential dkms linux-headers-"${kver}" >>"${LOG_FILE}" 2>&1 \
                || die "Не удалось поставить linux-headers-${kver}. Поставьте вручную."
        else
            die "Заголовки ядра обязательны для сборки модуля: /lib/modules/${kver}/build"
        fi
    fi
    ok "Заголовки ядра: ${srcdir}"
    command -v gcc >/dev/null 2>&1 || apt-get install -y build-essential >>"${LOG_FILE}" 2>&1 || die "Нет gcc"
    ok "Тулчейн сборки на месте"
}

# =============================================================================
#  Nouveau
# =============================================================================
handle_nouveau() {
    step "Nouveau — блокировка"
    if lsmod | grep -q '^nouveau '; then
        warn "nouveau загружен. Блокирую и прошу перезагрузку."
        cat > /etc/modprobe.d/blacklist-nouveau-cmp90hx.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
        update-initramfs -u >>"${LOG_FILE}" 2>&1 || true
        echo ""
        echo -e "${YELLOW}>>> ПЕРЕЗАГРУЗИТЕ машину и запустите скрипт снова.${NC}"
        echo -e "${YELLOW}>>> Это ожидаемое поведение (см. README cmp90hx_pwner).${NC}"
        exit 3
    fi
    if [ ! -f /etc/modprobe.d/blacklist-nouveau-cmp90hx.conf ]; then
        cat > /etc/modprobe.d/blacklist-nouveau-cmp90hx.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
        update-initramfs -u >>"${LOG_FILE}" 2>&1 || true
        ok "nouveau заблокирован (уже загруженной копии нет — можно продолжать)"
    else
        ok "nouveau уже заблокирован"
    fi
}

# =============================================================================
#  cmp90hx-unlock: локально или клон
# =============================================================================
locate_unlock_repo() {
    step "cmp90hx-unlock — поиск репозитория"
    local cand
    # Локальная раскладка: CMP90HX_HOME/cmp90hx-unlock/cmp90hx-unlock/install.sh
    for cand in "${CMP90HX_HOME}/cmp90hx-unlock/cmp90hx-unlock" "${CMP90HX_HOME}/cmp90hx-unlock"; do
        if [ -f "${cand}/install.sh" ] && [ -d "${cand}/driver/patches/cmp90-rejoin15" ]; then
            UNLOCK_REPO="${cand}"
            ok "Найден: ${UNLOCK_REPO}"
            return 0
        fi
    done
    warn "Рядом с MyCMP90 репозиторий не найден — клонирую ${UNLOCK_REPO_URL}"
    git clone --depth 1 "${UNLOCK_REPO_URL}" "${WORKDIR}/cmp90hx-unlock" >>"${LOG_FILE}" 2>&1 \
        || die "Не удалось склонировать. Положите репозиторий в ${CMP90HX_HOME}/cmp90hx-unlock"
    UNLOCK_REPO="${WORKDIR}/cmp90hx-unlock"
    ok "Склонирован: ${UNLOCK_REPO}"
}

# =============================================================================
#  Userspace 610.43.03 + GSP firmware
# =============================================================================
ensure_userspace() {
    step "Userspace + GSP firmware ${DRIVER_VERSION}"
    local gsp="/lib/firmware/nvidia/${DRIVER_VERSION}/gsp_ga10x.bin"
    local libcuda
    libcuda="$(ldconfig -p 2>/dev/null | grep -m1 'libcuda.so.1' || true)"

    if [ -f "${gsp}" ] && [ -n "${libcuda}" ]; then
        ok "GSP firmware и libcuda уже установлены"
        return 0
    fi

    warn "Требуется userspace ${DRIVER_VERSION} — скачиваю .run пакет"
    local run_pkg="${WORKDIR}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
    if [ ! -f "${run_pkg}" ]; then
        curl -fL --retry 3 -o "${run_pkg}" "${RUN_URL}" >>"${LOG_FILE}" 2>&1 \
            || die "Не удалось скачать ${RUN_URL}"
    fi
    chmod +x "${run_pkg}"
    info "Установка userspace (--no-kernel-modules, модуль соберёт cmp90hx-unlock)"
    sh "${run_pkg}" --silent --no-kernel-modules >>"${LOG_FILE}" 2>&1 \
        || die "Установка userspace провалилась — смотрите лог"
    ok "Userspace + GSP firmware ${DRIVER_VERSION} установлены"
}

# =============================================================================
#  Установка патченного драйвера (rejoin15)
# =============================================================================
install_driver() {
    step "Сборка и установка патченного драйвера (profile=cmp90-rejoin15)"
    info "Может занять 5–20 минут (сборка nvidia-open 610.43.03)…"
    ( cd "${UNLOCK_REPO}" && ./install.sh --profile=cmp90-rejoin15 ) >>"${LOG_FILE}" 2>&1 \
        || die "install.sh --profile=cmp90-rejoin15 завершился с ошибкой — смотрите лог"
    ok "Драйвер с rejoin15 установлен и загружен"
}

# =============================================================================
#  Верификация
# =============================================================================
verify() {
    step "Верификация"
    if bash "${STACK_DIR}/check.sh"; then
        echo ""
        ok "КОМПЬЮТ-АНЛОК РАБОТАЕТ. Стек персистентен — переживёт перезагрузку."
    else
        warn "check.sh сообщил о проблемах — проверьте вывод выше и dmesg | grep -i cmp90"
    fi
}

next_steps() {
    step "Дальнейшие шаги"
    cat <<EOF
  1. Бенчмарк до/после:      ./bench.sh            (модель: LLAMA_MODEL=/path/model.gguf ./bench.sh)
  2. Энерголимит 200 Вт:     sudo ./power.sh 200   (≈96% производительности, тише и холоднее)
  3. Две карты + P2P:        sudo ./p2p-setup.sh, затем ./run-vllm-tp2.sh
  4. Полный лог установки:   ${LOG_FILE}
EOF
}

# =============================================================================
main() {
    echo -e "${BOLD}"
    cat <<'EOF'
  ╔══════════════════════════════════════════════════════════════════╗
  ║   MyCMP90 STACK INSTALLER — CMP 90HX compute unlock (rejoin15)   ║
  ║   610.43.03, V67 inline, персистентно. pp512: 224 → 1770 t/s     ║
  ╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    preflight

    if [ "${1:-}" = "--preflight" ]; then
        ok "Preflight пройден (--preflight: установка не выполнялась)"
        exit 0
    fi

    handle_nouveau
    locate_unlock_repo
    ensure_userspace
    install_driver
    verify
    next_steps
}

main "$@"
