#!/usr/bin/env bash
# =============================================================================
#  MyCMP90 power — управление power limit CMP 90HX
# =============================================================================
#  TDP карты 250–320 Вт, инференс импульсный. Лимит 180–200 Вт сохраняет
#  ~96% производительности инференса и снижает нагрев GDDR6X на 10–15°C.
#
#  Использование:
#    sudo ./power.sh 200        # установить лимит 200 Вт на все CMP 90HX
#    sudo ./power.sh show       # показать текущие лимиты/потребление
#    sudo ./power.sh persist 200  # установить + systemd-юнит на каждую загрузку
#    sudo ./power.sh unpersist    # убрать systemd-юнит
# =============================================================================
set -euo pipefail

UNIT="/etc/systemd/system/nvidia-cmp90-power-limit.service"
GPU_DEVID="0x220d"

color() { if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '%b' "$1"; else printf '%s' ""; fi }
ok()   { echo "$(color '\033[0;32m[ OK ]\033[0m')  $*"; }
err()  { echo "$(color '\033[0;31m[FAIL]\033[0m')  $*" >&2; exit 1; }

cmp90_indexes() {
    # индексы CMP 90HX из nvidia-smi по PCI bus_id
    python3 - <<'PY'
import subprocess
out = subprocess.check_output(
    ["nvidia-smi", "--query-gpu=index,pci.bus_id", "--format=csv,noheader"], text=True)
bdfs = subprocess.run(
    ["bash", "-c",
     "for d in /sys/bus/pci/devices/*; do "
     "[ \"$(cat $d/vendor 2>/dev/null)\" = 0x10de ] && "
     "[ \"$(cat $d/device 2>/dev/null)\" = 0x220d ] && basename $d; done"],
    capture_output=True, text=True).stdout.split()
for line in out.strip().splitlines():
    idx, bus = [x.strip() for x in line.split(",")]
    bus_short = bus.replace("00000000:", "").replace("0000:", "").upper()
    if any(b.replace("0000:", "").upper() in bus_short or bus_short in b.upper() for b in bdfs):
        print(idx)
PY
}

show() {
    nvidia-smi --query-gpu=index,name,power.draw,power.limit,power.default_limit,power.min_limit,power.max_limit,temperature.gpu \
        --format=csv 2>/dev/null || err "nvidia-smi недоступен"
}

set_limit() {
    [ "$(id -u)" -eq 0 ] || err "Запустите как root: sudo $0 $*"
    local watts="$1"
    command -v nvidia-smi >/dev/null 2>&1 || err "nvidia-smi недоступен"
    local idx rc_any=0
    for idx in $(cmp90_indexes); do
        if nvidia-smi -i "${idx}" -pl "${watts}" >/dev/null 2>&1; then
            ok "GPU${idx}: power limit = ${watts} Вт"
        else
            echo "  GPU${idx}: не удалось установить (см. nvidia-smi -q -d POWER — допустимый диапазон)"; rc_any=1
        fi
    done
    show
    return "${rc_any}"
}

persist() {
    local watts="$1"
    set_limit "${watts}"
    cat > "${UNIT}" <<EOF
[Unit]
Description=CMP 90HX power limit ${watts}W (MyCMP90)
After=multi-user.target
Requires=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pl ${watts}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable nvidia-cmp90-power-limit.service >/dev/null
    ok "Лимит ${watts} Вт будет применяться при каждой загрузке (${UNIT})"
}

unpersist() {
    [ "$(id -u)" -eq 0 ] || err "Запустите как root"
    systemctl disable --now nvidia-cmp90-power-limit.service 2>/dev/null || true
    rm -f "${UNIT}"
    systemctl daemon-reload
    ok "Юнит убран"
}

case "${1:-show}" in
    show)      show ;;
    persist)   [ -n "${2:-}" ] || err "Использование: sudo $0 persist <ватт>"; persist "$2" ;;
    unpersist) unpersist ;;
    ''|help|-h|--help)
        sed -n '2,15p' "$0" | sed 's/^#//;s/^ //'; exit 0 ;;
    *)
        if ! [[ "${1}" =~ ^[0-9]+$ ]]; then err "Неизвестная команда: $1 (см. $0 --help)"; fi
        set_limit "$1" ;;
esac
