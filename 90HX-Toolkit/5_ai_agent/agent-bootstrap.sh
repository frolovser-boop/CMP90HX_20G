#!/usr/bin/env bash
# =============================================================================
#  agent-bootstrap.sh — подготовка Ubuntu-сервера для работы ИИ-агента
#  (CMP 90HX). Выполняется ОДИН раз, от root, на самом сервере
#  (или по SSH:  ssh root@HOST 'bash -s' < agent-bootstrap.sh --user agent)
#
#  Что делает:
#    1. apt-пакеты: openssh-server, build-essential, headers, python3, git,
#       pciutils, lm-sensors, curl, net-tools
#    2. Пользователь для агента (по умолчанию `agent`) с sudo без пароля
#       (опция --no-nopasswd отключает; тогда агент будет просить пароль sudo)
#    3. Каталоги /opt/mycmp90/{stack,logs,tools} + копия скриптов стека
#       из соседнего каталога 3_linux_server (если toolkit загружен на сервер)
#    4. Клон/обновление cmp90hx-unlock (нужен install.sh rejoin15) и cmp90hx
#       (bendy2, нужен rm_issue_rate_query.py для check.sh)
#    5. SSH: убеждиться, что sshd запущен и разрешает pubkey-авторизацию
#
#  Использование:
#    sudo ./agent-bootstrap.sh                 # пользователь agent
#    sudo ./agent-bootstrap.sh --user ivan
#    sudo ./agent-bootstrap.sh --no-nopasswd   # sudo по паролю
# =============================================================================
set -uo pipefail

AGENT_USER="agent"
NOPASSWD=1
while [ $# -gt 0 ]; do
    case "$1" in
        --user)        AGENT_USER="${2:?}"; shift 2 ;;
        --no-nopasswd) NOPASSWD=0; shift ;;
        -h|--help)     sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Неизвестный аргумент: $1"; exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || { echo "FAIL: запустите как root (sudo)"; exit 1; }
. /etc/os-release 2>/dev/null && echo "OS: ${PRETTY_NAME:-?}"
command -v apt-get >/dev/null || { echo "FAIL: нужен Debian/Ubuntu (apt)"; exit 1; }

ok()   { echo "[ OK ] $*"; }
step() { echo "---- $* ----"; }

# ---- 1. Пакеты --------------------------------------------------------------
step "1/5 apt-пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y openssh-server build-essential dkms linux-headers-"$(uname -r)" \
                   python3 python3-pip git curl pciutils lm-sensors net-tools \
                   ca-certificates
ok "пакеты установлены"

# ---- 2. Пользователь агента --------------------------------------------------
step "2/5 пользователь ${AGENT_USER}"
if id "${AGENT_USER}" &>/dev/null; then
    ok "уже существует"
else
    useradd -m -s /bin/bash -G sudo "${AGENT_USER}"
    ok "создан (в группе sudo). Пароль не установлен — вход только по ключу."
fi
SUDOERS="/etc/sudoers.d/90-${AGENT_USER}-cmp90"
if [ "${NOPASSWD}" -eq 1 ]; then
    echo "${AGENT_USER} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS}"
    chmod 440 "${SUDOERS}"
    ok "sudo без пароля: ${SUDOERS} (закомментируйте строку, чтобы отключить)"
else
    rm -f "${SUDOERS}"
    ok "sudo по паролю"
fi

# ---- 3. Каталоги проекта -----------------------------------------------------
step "3/5 /opt/mycmp90"
mkdir -p /opt/mycmp90/{stack,logs,tools}
chown -R "${AGENT_USER}:${AGENT_USER}" /opt/mycmp90
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_SRC="${SELF_DIR}/../3_linux_server"
if [ -d "${STACK_SRC}" ]; then
    cp -f "${STACK_SRC}"/*.sh /opt/mycmp90/stack/ 2>/dev/null && \
        chmod +x /opt/mycmp90/stack/*.sh && ok "скрипты стека скопированы в /opt/mycmp90/stack"
else
    echo "  [WARN] ${STACK_SRC} не найден — скопируйте *.sh из 3_linux_server вручную"
fi

# ---- 4. Репозитории ----------------------------------------------------------
step "4/5 cmp90hx-unlock + cmp90hx (bendy2)"
if [ ! -d /opt/mycmp90/cmp90hx-unlock ]; then
    git clone --depth 1 https://github.com/WildFlash1st/cmp90hx-unlock.git \
        /opt/mycmp90/cmp90hx-unlock && ok "cmp90hx-unlock склонирован"
else
    ok "cmp90hx-unlock уже есть"
fi
if [ ! -f /opt/mycmp90/tools/rm_issue_rate_query.py ]; then
    git clone --depth 1 https://github.com/bendy2/cmp90hx.git /opt/mycmp90/cmp90hx-bendy2 \
        && cp /opt/mycmp90/cmp90hx-bendy2/scripts/rm_issue_rate_query.py /opt/mycmp90/tools/ \
        && ok "rm_issue_rate_query.py на месте"
else
    ok "rm_issue_rate_query.py уже есть"
fi

# ---- 5. SSH ------------------------------------------------------------------
step "5/5 sshd"
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null
grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config || \
    echo "  [INFO] проверьте PubkeyAuthentication yes в /etc/ssh/sshd_config"
systemctl is-active ssh >/dev/null 2>&1 && ok "ssh активен" || systemctl is-active sshd >/dev/null 2>&1 && ok "sshd активен"
echo ""
echo "Дальше (с рабочей Windows-машины): см. README.md раздел «SSH-доступ»."
echo "Проверка агента:  ssh ${AGENT_USER}@<host> 'sudo /opt/mycmp90/agent-status.sh'"
