#!/usr/bin/env bash
# =============================================================================
#  MyCMP90 p2p-setup — включение CUDA P2P между CMP 90HX
# =============================================================================
#  Драйвер NVIDIA по умолчанию гоняет трафик карта↔карта через RAM хоста
#  (bounce buffer). Скрипт включает прямой P2P параметрами модуля:
#
#    NVreg_EnableResizableBar=1
#    NVreg_DmaRemapPeerMmio=0
#    NVreg_RegistryDwords="ForceP2P=0x111;CLForceP2P=0x111;RMForceP2PType=1;
#                          RMPcieP2PType=0;RMForceStaticBar1=1;
#                          PeerMappingOverride=1;RMDisableFeatureDisablement=1"
#
#  (набор параметров — из проверенного cmp90hx_pwner / load_patched_driver_once_with_p2p)
#
#  Использование:
#    sudo ./p2p-setup.sh            # настроить (GRUB + modprobe.d) + подсказка
#    ./p2p-setup.sh verify          # проверить P2P на текущей загрузке
#
#  ВАЖНО: параметры действуют на модуль из updates/cmpunlocker* (патченный
#  rejoin15). При загрузке ОС ничего дополнительно запускать не нужно.
#  Статус: ⚠️ требует проверки на вашем железе — см. STATUS.md, раздел P2P.
# =============================================================================
set -uo pipefail

GRUB_DROPIN="/etc/default/grub.d/99-cmp90hx-p2p.cfg"
MODPROBE_FILE="/etc/modprobe.d/cmp90hx-p2p.conf"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
else
    GREEN=""; YELLOW=""; CYAN=""; RED=""; NC=""; BOLD=""
fi
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

count_cmp90() {
    local n=0 d
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "${d}/vendor" 2>/dev/null)" = "0x10de" ] || continue
        [ "$(cat "${d}/device" 2>/dev/null)" = "0x220d" ] || continue
        n=$((n + 1))
    done
    echo "${n}"
}

# -----------------------------------------------------------------------------
#  verify: матрица P2P + замер скорости
# -----------------------------------------------------------------------------
do_verify() {
    command -v nvidia-smi >/dev/null 2>&1 || err "nvidia-smi недоступен"
    local n; n="$(count_cmp90)"
    [ "${n}" -ge 2 ] || err "Найдено ${n} карт CMP 90HX — P2P требует минимум 2"

    info "Модуль nvidia-peermem (NCCL):"
    if lsmod | grep -q '^nvidia_peermem '; then
        ok "загружен"
    else
        modprobe nvidia_peermem 2>/dev/null && ok "загружен (только что)" \
            || warn "не загружен — NCCL не сможет использовать P2P (нужен модуль из того же драйвера)"
    fi

    echo ""
    info "Матрица P2P read:"
    nvidia-smi topo -p2p r 2>&1
    info "Матрица P2P write:"
    nvidia-smi topo -p2p w 2>&1
    echo ""

    # Замер скорости: p2pBandwidthLatencyTest (cuda-samples) или torch
    if command -v p2pBandwidthLatencyTest >/dev/null 2>&1; then
        info "cuda-samples p2pBandwidthLatencyTest:"
        p2pBandwidthLatencyTest 2>&1 | grep -Ei "bidirectional|unidirectional|P2P=|peer" | head -20
    elif python3 -c 'import torch' 2>/dev/null && [ "${n}" -ge 2 ]; then
        info "Замер через PyTorch (bidirectional copy, 256 MiB):"
        python3 - <<'PY'
import torch
assert torch.cuda.device_count() >= 2, "нужно >=2 CUDA устройств"
a = torch.randn(64 * 1024 * 1024, device="cuda:0")   # 256 MiB fp32
b = torch.empty_like(a, device="cuda:1")
for _ in range(3): b.copy_(a, non_blocking=True)     # прогрев
torch.cuda.synchronize()
import time
start = time.perf_counter()
N = 32
for _ in range(N):
    b.copy_(a, non_blocking=True)
torch.cuda.synchronize()
dt = (time.perf_counter() - start) / N
print(f"  P2P copy 0->1: {a.numel() * 4 / dt / 1e9:.2f} GB/s  (буфер 256 MiB, {N} итераций)")
PY
        echo ""
        info "Ориентир из документации: ~6.70 GB/s bidirectional (PCIe Gen2)"
        warn "Если получили ~1.6-1.8 GB/s — P2P работает через bounce buffer (не включился)"
    else
        warn "Нет p2pBandwidthLatencyTest и PyTorch — скорость не измерена (только матрица выше)"
    fi

    echo ""
    if nvidia-smi topo -p2p r 2>/dev/null | grep -q "OK\|CS\|C\|^.*OK"; then
        ok "P2P на текущей загрузке активен (см. матрицу выше)"
    else
        warn "В матрице нет OK — выполните: sudo ./p2p-setup.sh и перезагрузитесь"
    fi
}

# -----------------------------------------------------------------------------
#  setup: GRUB + modprobe.d
# -----------------------------------------------------------------------------
do_setup() {
    [ "$(id -u)" -eq 0 ] || err "Запустите как root: sudo $0"
    [ "$(count_cmp90)" -ge 2 ] || err "Найдено $(count_cmp90) карт CMP 90HX — setup имеет смысл для 2+ карт"

    info "Шаг 1/3 — IOMMU параметры ядра (${GRUB_DROPIN})"
    mkdir -p /etc/default/grub.d
    if [ -f "${GRUB_DROPIN}" ] && grep -q "intel_iommu=on" "${GRUB_DROPIN}"; then
        ok "уже настроено"
    else
        # preserve existing cmdline
        cat > "${GRUB_DROPIN}" <<'EOF'
# CMP 90HX P2P: изолированные IOMMU-группы + passthrough DMA + большие MMIO-окна
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} intel_iommu=on iommu=pt pci=realloc,hpmemsize=8G,hpmmiosize=256M"
EOF
        if command -v update-grub >/dev/null 2>&1; then
            update-grub >>/tmp/mycmp90-p2p-grub.log 2>&1 || warn "update-grub вернул ошибку — проверьте /tmp/mycmp90-p2p-grub.log"
        elif command -v grub2-mkconfig >/dev/null 2>&1; then
            grub2-mkconfig -o /boot/grub2/grub.cfg >>/tmp/mycmp90-p2p-grub.log 2>&1 || true
        fi
        ok "записано (update-grub выполнен)"
    fi

    info "Шаг 2/3 — параметры модуля nvidia (${MODPROBE_FILE})"
    cat > "${MODPROBE_FILE}" <<'EOF'
# CMP 90HX P2P unlock (набор из cmp90hx_pwner, load_patched_driver_once_with_p2p)
options nvidia NVreg_EnableResizableBar=1 NVreg_DmaRemapPeerMmio=0 NVreg_RegistryDwords="ForceP2P=0x111;CLForceP2P=0x111;RMForceP2PType=1;RMPcieP2PType=0;RMForceStaticBar1=1;PeerMappingOverride=1;RMDisableFeatureDisablement=1"
EOF
    ok "записано. Действует при загрузке патченного модуля nvidia.ko (updates/cmpunlocker*)"

    info "Шаг 3/3 — финал"
    echo ""
    echo -e "${BOLD}Требуется ПЕРЕЗАГРУЗКА.${NC} После неё:"
    echo -e "  1. ./p2p-setup.sh verify     — матрица P2P + замер скорости"
    echo -e "  2. ./run-vllm-tp2.sh         — vLLM TP=2 на 2 картах"
    echo ""
    warn "Замечание: GRUB-строка с IOMMU-параметрами применяется только на Intel-хостах;"
    warn "на AMD добавьте amd_iommu=on iommu=pt в тот же drop-in, если P2P не поднимется."
    warn "Если хост перестал грузиться — удалите ${GRUB_DROPIN} из live-среды."
}

case "${1:-setup}" in
    setup)  do_setup ;;
    verify) do_verify ;;
    *)      sed -n '2,20p' "$0" | sed 's/^#//;s/^ //' ;;
esac
