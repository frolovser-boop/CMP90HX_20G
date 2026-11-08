# QUICKSTART — «у меня CMP 90HX, с чего начать»

Три сценария по возрастанию сложности. Проверенные статусы методов —
[`STATUS.md`](STATUS.md); правила безопасности — [`DISCLAIMER.md`](DISCLAIMER.md)
(прочитайте первым).

---

## Сценарий A: Compute unlock + инференс (Linux) — ✅ готовый путь

**Нужно:** карта CMP 90HX, ПК/сервер с Ubuntu 20.04/22.04/24.04 (или Debian 11/12),
Secure Boot **выключен** в BIOS, интернет, заголовки ядра ставятся автоматически.

```bash
git clone https://github.com/frolovser-boop/CMP90HX_20G.git
cd CMP90HX_20G/90HX-Toolkit/3_linux_server
sudo ./install-unlock.sh          # 10–20 мин: драйвер 610.43.03 + rejoin15
sudo ./check.sh                   # ожидание: PASS, 9/9 полей = full
LLAMA_MODEL=/path/model.gguf ./bench.sh   # pp512 должен вырасти ~8×
sudo ./power.sh persist 200       # энерголимит 200 Вт (тише и холоднее)
```

Две карты? → `sudo ./p2p-setup.sh` → перезагрузка → `./p2p-setup.sh verify` →
`./run-vllm-tp2.sh` (или PP-разбивка — см. `docs/CMP50HX_VS_90HX.md` §4).

Первый запуск может попросить перезагрузку (блокировка nouveau) — это штатно:
перезагрузитесь и запустите скрипт снова.

## Сценарий B: диагностика памяти (загрузочная флешка) — ✅ методика готова, образ качается отдельно

**Нужно:** флешка ≥8 ГБ, ПК с iGPU (у CMP нет видеовыходов — тестируемая карта
всегда «вторичная»), Secure Boot off.

1. Скачайте образ по ссылкам первоисточника:
   [levirepair.eu thread 3](https://levirepair.eu/infusions/forum/viewthread.php?thread_id=3)
   (также зеркала и альтернативные сборки:
   [vlab.su thread 124090](https://vlab.su/viewtopic.php?t=124090&f=48)).
   Сверьте MD5: `3cc2ce1e4b9836548a8fad6479a2c4c3`.
2. Залейте Rufus'ом (DD-режим) — Rufus и пошаговая инструкция:
   [`90HX-Toolkit/1_usb_diagnostics/`](90HX-Toolkit/1_usb_diagnostics/README.md).
3. Загрузитесь → `modsinit` → `mods -test 275 -pstate 0.max` (память) —
   расшифровка результатов и карты «ошибка → чип»:
   [`90HX-Toolkit/4_memory_maps/`](90HX-Toolkit/4_memory_maps/README.md) и
   [`docs/MATS_MODS_FIELD_GUIDE.md`](docs/MATS_MODS_FIELD_GUIDE.md).

## Сценарий C: 20GB-мод — ⚠️ дорожная карта, НЕ для новичков

**Нужно:** инфракрасная BGA-станция, опыт реболлинга, 10× Micron **D8BZC**
(MT61K512M32KPA-21:U, 16 Гбит, 21 Gbps — не путать с D8BGW, это 8 Гбит!),
программатор SPI, дамп стокового VBIOS.

Читаете по порядку:
1. [`docs/20GB_PROCEDURE.md`](docs/20GB_PROCEDURE.md) — полная процедура с
   контрольными точками и откатом
2. [`MEMORY_MOD_20GB.md`](MEMORY_MOD_20GB.md) — теория (страпы, BCT, WPR2)
3. [`docs/MATS_MODS_FIELD_GUIDE.md`](docs/MATS_MODS_FIELD_GUIDE.md) §6 — чипы и монтаж

⚠️ Незакрытые звенья (честно): инженерный VBIOS RTX 3080 20GB с BCT под 16 Гбит
ищется на ремонтных форумах (в репо нет); патч динамического WPR2 под GA102
существует пока только как план адаптации с CMP 50HX
([`STATUS.md`](STATUS.md) раздел 4). На 90HX мод никем публично не воспроизведён.

## Сценарий D: сервер + ИИ-агент по SSH

[`90HX-Toolkit/5_ai_agent/`](90HX-Toolkit/5_ai_agent/README.md) — bootstrap
сервера, статус-отчёты, runbook `AGENTS.md` (агент сам ставит стек и
диагностирует; VBIOS/пайка — только за человеком).

---

## Внешние зависимости репозитория

| Зависимость | Откуда | Кто подтягивает |
|---|---|---|
| cmp90hx-unlock (патчи rejoin15, драйвер 610.43.03) | github.com/WildFlash1st/cmp90hx-unlock | `install-unlock.sh` клонирует сам |
| rm_issue_rate_query.py (проверка 9 полей) | github.com/bendy2/cmp90hx | `check.sh` ищет локально, иначе скачивает |
| Драйвер NVIDIA Open 610.43.03 | download.nvidia.com | `install-unlock.sh` |
| Образ диагностической флешки | levirepair.eu / vlab.su (ссылки выше) | скачиваете вручную |
| Инженерный VBIOS RTX 3080 20GB (BCT 16Gb) | ремонтные форумы | вручную (только для сценария C) |

Если какой-то внешний репозиторий исчез — поднимайте issue; структура зависимостей
описана здесь же.
