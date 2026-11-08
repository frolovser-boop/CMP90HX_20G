# 5. Инструменты ИИ-агента (сервер Ubuntu, доступ по SSH)

Набор для работы ИИ-агента с картами CMP 90HX по SSH: подготовка сервера,
полный статус-отчёт, правила и сценарии.

## Состав

| Файл | Назначение |
| :--- | :--- |
| `agent-bootstrap.sh` | Выполнить **один раз на сервере** (root): пакеты, пользователь `agent` с sudo, `/opt/mycmp90/{stack,logs,tools}`, клон cmp90hx-unlock + rm_issue_rate_query.py, sshd |
| `agent-status.sh` | Полный статус-отчёт для агента: HOST / GPU / PCI / DRIVER / **UNLOCK** / THERMAL / P2P / TOOLS. `--save` пишет копию в `/opt/mycmp90/logs/` |
| `AGENTS.md` | **Runbook для агента**: правила безопасности, каталог команд с ожидаемыми результатами, сценарии A–F, формат отчёта, известные грабли |

## Порядок внедрения (со стороны Windows)

### Шаг 1. SSH-доступ с Windows

```powershell
# 1) Ключ (если ещё нет):
ssh-keygen -t ed25519

# 2) Скопировать публичный ключ на сервер (пароль один раз):
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@<host> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"

# 3) Псевдоним в C:\Users\<вы>\.ssh\config:
#   Host cmp90
#       HostName <IP сервера>
#       User agent
#       IdentityFile ~/.ssh/id_ed25519
```
Проверка: `ssh cmp90 "echo ok"`.

### Шаг 2. Загрузить toolkit на сервер и выполнить bootstrap

```powershell
scp -r 90HX-Toolkit cmp90:/tmp/
ssh cmp90
sudo bash /tmp/90HX-Toolkit/5_ai_agent/agent-bootstrap.sh   # или --user <имя>
exit
```

### Шаг 3. Проверить глазками агента

```
ssh cmp90 "sudo /opt/mycmp90/agent-status.sh --save"
```

### Шаг 4. Дать агенту задание

В сессии агента (ZCode/CLI) указать: хост-псевдоним (`cmp90`), путь к
`AGENTS.md` (например, 90HX-Toolkit/5_ai_agent/AGENTS.md из этого репозитория)
и задачу — «проведи сценарий A из AGENTS.md». Дальше агент работает по
runbook: статус → установка стека → проверка → power limit → отчёт.

## Что агент МОЖЕТ сам / что требует человека

| Агент сам (по SSH) | Только человек |
| :--- | :--- |
| статус/диагностика, check.sh, бенчмарки, power limit 150–250 Вт, p2p-setup + verify, установка стека, разбор логов | физические действия, перезагрузка (согласование), флешка MODS, любые VBIOS/прошивки, пайка, ввод пароля sudo (если --no-nopasswd) |

Полный список правил — `AGENTS.md`, раздел 2.
