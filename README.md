# Комплексное исследование модификации NVIDIA CMP 90HX для задач AI-инференса

Данный репозиторий аккумулирует результаты глубокого анализа архитектуры, прошивок, драйверов и аппаратной части видеокарты **NVIDIA CMP 90HX** (архитектура Ampere, чип GA102, референсная плата PG132), а также опыт смежных проектов (`cmp90hx-unlock`, `cmp90hx_pwner`, `cmp50hx-unlock`, `nv-uefi-unlocker`).

Цель проекта: адаптация и разгон карты для эффективного и экономичного **инференса нейросетей (LLM, Vision, Diffusion)**.

> **Готовые скрипты лежат в [`stack/`](stack/)** — установка, проверка, бенчмарки, P2P.
> **Собранный набор утилит: [`90HX-Toolkit/`](90HX-Toolkit/README.md)** — USB-диагностика (Rufus+инструкция), VBIOS-инструменты, Linux-стек, схемы памяти, инструменты ИИ-агента — с SHA256-манифестом.

## ⚠️ О публикации в публичный репозиторий

* **MODS/MATS/NVMT-бинарники в репозиторий НЕ включены** (проприетарные
  инструменты NVIDIA) — в документации даны только указатели на локальные
  каталоги (`../455.219/`, `../MODS - NVMT - Rufus/`, `../MATS_MODS_NVMT/`,
  помечены «вне репозитория»).
* В `90HX-Toolkit/` лежат сторонние бинарники: `rufus-3.21.exe` (GPLv3,
  распространение допустимо; надёжнее давать ссылку на [официальный релиз](https://github.com/pbatard/rufus/releases)),
  `OMGVflash.zip` и `nvflashk-main.zip` (переработки инструментов NVIDIA —
  распространение в серой зоне). Перед публикацией решите: включать или
  заменить ссылками.
* Методы compute unlock описаны в исследовательских целях; eFuse не
  перепрограммируются, состояние стока восстанавливаемо.

---

## ✅⚠️❌ Статус утверждений (факты, а не планы)

| Возможность | Статус | Чем подтверждено |
| :--- | :--- | :--- |
| Compute Unlock (снятие SM Issue-Rate Throttling) | ✅ **Проверено, персистентно** | `cmp90hx-unlock/STATUS.md`: rejoin15 на драйвере Open 610.43.03, 9/9 полей FULL, pp512 **224 → 1770 t/s (~7.9×)**, tg16 **55.5 t/s** |
| Полная скорость Tensor Cores (FP16/BF16/TF32/INT8) | ✅ Проверено | Бенчмарк GEMM после анлока (~29.8 TFLOPS FP32, ~115 TFLOPS FP16 Tensor) |
| P2P между картами (ForceP2P / PeerMappingOverride) | ⚠️ Реализовано в `cmp90hx_pwner`, на 90HX требует перепроверки на вашем железе | Матрица `nvidia-smi topo -p2p` должна показать `OK`; скрипт `stack/p2p-setup.sh` делает это автоматом |
| PCIe Gen2 x16 (~7 ГБ/с) | ⚠️ Проверяемо, метод есть | Конфликт бенчей разгадан: pwner открывает маску XVE `0x00088FE8` V67-цепочкой (SUCCESS с тройной верификацией), cmp90hx-unlock тестировал другой регистр (`XP3G 0x8E1B0`). Проверка на своём экземпляре — разбор: [`docs/PCIE_SOLDERING_ANALYSIS.md`](docs/PCIE_SOLDERING_ANALYSIS.md) |
| Мод 20 ГБ (перепайка на 16Gb чипы) | ⚠️ Теория. Проверен только на CMP 50HX (TU102) | План в [`MEMORY_MOD_20GB.md`](MEMORY_MOD_20GB.md), процедура с контрольными точками: [`docs/20GB_PROCEDURE.md`](docs/20GB_PROCEDURE.md) |
| Compute Unlock под Windows | ⚠️ План, реализации для 90HX нет | UEFI-путь описан в [`COMPUTE_UNLOCK.md`](COMPUTE_UNLOCK.md) (вариант 3); план портирования: [`docs/UEFI_WINDOWS_PLAN.md`](docs/UEFI_WINDOWS_PLAN.md) |

**Единственный источник истины по фактическому состоянию:** `E:\GIT\CMP90HX\cmp90hx-unlock\cmp90hx-unlock\STATUS.md` (дата последней верификации: 2026-08-16).

---

## 📑 Структура документации проекта

| Документ | Описание | Статус |
| :--- | :--- | :--- |
| 🚀 **[COMPUTE_UNLOCK.md](COMPUTE_UNLOCK.md)** | Снятие вычислительного ограничения (SM Issue-Rate Throttling): эксплойт V67, сравнение подходов (bendy2, rejoin15, cmp90hx_pwner, UEFI-анлок) | ✅ Метод rejoin15 подтверждён |
| ⚡ **[PCIE_AND_P2P.md](PCIE_AND_P2P.md)** | PCIe Gen2 retrain и включение P2P: механизмы, параметры драйвера, проверка | ⚠️ Gen2 под вопросом, P2P реализуем |
| 🛠️ **[MEMORY_MOD_20GB.md](MEMORY_MOD_20GB.md)** | Перепайка 10→20 ГБ GDDR6X: чипы Micron 16Gb, страпы RAMCFG, BCT/VBIOS, WPR2 | ⚠️ Теория (проверено на 50HX) |
| 🤖 **[INFERENCE_GUIDE.md](INFERENCE_GUIDE.md)** | Запуск инференса: vLLM, Ollama, llama.cpp, ExLlamaV2; квантование; модели 7B–70B; power limit | ✅ Применим сразу после анлока |
| 📋 **[STATUS.md](STATUS.md)** | Трекер верификации каждого утверждения документации | — |
| 🧭 **[docs/MATS_MODS_FIELD_GUIDE.md](docs/MATS_MODS_FIELD_GUIDE.md)** | Полевой справочник диагностики памяти из треда VLab (30 стр.): версии, MODS-vs-MATS, TRAINING_STATUS, питание, чипы | Выжим форума |
| 🔧 **[docs/PCIE_SOLDERING_ANALYSIS.md](docs/PCIE_SOLDERING_ANALYSIS.md)** | Анализ «можно ли пайкой разблокировать шину»: x16 уже полная, замок — в маске XVE `0x88FE8`; decision tree | Анализ |
| ⚖️ **[docs/CMP50HX_VS_90HX.md](docs/CMP50HX_VS_90HX.md)** | Сравнение 50HX vs 90HX и решение «2×50HX + 20GB-моды или 90HX» при равной цене | Решение о закупке |
| 🧪 **[docs/DIAG_TOOLS_MATS_NVMT.md](docs/DIAG_TOOLS_MATS_NVMT.md)** | Разбор пакета фирменной диагностики памяти: GA102 не поддержан, пакет для трека 50HX | Анализ |
| 🪟 **[docs/UEFI_WINDOWS_PLAN.md](docs/UEFI_WINDOWS_PLAN.md)** | План Windows-анлока через UEFI (портирование цепочки GA102) | План |
| 🩹 **[docs/20GB_PROCEDURE.md](docs/20GB_PROCEDURE.md)** | Процедура 10→20 ГБ с контрольными точками и диагностикой сбоев | Не проверено на 90HX |

### Готовые скрипты: [`stack/`](stack/)

| Скрипт | Назначение |
| :--- | :--- |
| `stack/install-unlock.sh` | Установка стека с нуля: Ubuntu/Debian → драйвер 610.43.03 + rejoin15 → проверка |
| `stack/check.sh` | Верификация: 9 полей Issue-Rate, PLM в dmesg, статус PCIe, инвентаризация |
| `stack/bench.sh` | Бенчмарки до/после: llama-bench (pp512/tg16), GEMM через PyTorch |
| `stack/power.sh` | Управление power limit (рекомендация: 200 Вт, ~96% производительности) |
| `stack/p2p-setup.sh` | Включение и проверка P2P для 2+ карт (IOMMU, RegistryDwords, topo-матрица) |
| `stack/run-vllm-tp2.sh` | Готовый запуск vLLM с Tensor Parallelism на 2 картах (Qwen2.5-32B-AWQ) |

---

## 🔍 Сводные технические характеристики CMP 90HX

| Параметр | Заводское состояние (сток) | После анлока (проверено) |
| :--- | :--- | :--- |
| **GPU / Архитектура** | GA102-100 (Ampere, sm_86, 8-нм Samsung) | Без изменений |
| **SM / CUDA ядра** | ~50–64 SM (до 8192 ядер) | Без изменений (SM не блокировались — блокировалась скорость выдачи инструкций) |
| **Тензорные ядра** | Issue-rate ~1/8 (eFuse троттлинг) | **100% скорость (FP16, BF16, TF32, INT8)** |
| **Шина памяти** | 320 бит (5 из 6 контроллеров FBP, 6-й прожжён eFuse — необратимо) | Без изменений |
| **Объем VRAM** | 10 ГБ GDDR6X | 10 ГБ (сток); 20 ГБ — только физическая перепайка, ⚠️ не проверено на 90HX |
| **Пропускная способность (ПСП)** | ~760 ГБ/с | ~760 ГБ/с (уровень RTX 3080) |
| **Интерфейс PCIe** | Gen1 x16 (~3.5 ГБ/с); ширина x16 полная (LnkCap `0x00453d01`), замок — только скорость | ⚠️ Gen2 через открытие маски XVE `0x88FE8` + retrain — проверить на своём экземпляре ([анализ](docs/PCIE_SOLDERING_ANALYSIS.md)) |
| **P2P между картами** | Заблокирован драйвером | ⚠️ Включается параметрами модуля (требует проверки) |
| **Видеовыходы / 3D PGRAPH** | Отсутствуют / заблокированы | Для CUDA-инференса не требуются |

---

## 📁 Обзор связанных репозиториев в `E:\GIT\CMP90HX`

* **`cmp90hx-unlock` (WildFlash1st):** ⭐ **Основной рабочий стек.** rejoin15 на драйвере Open 610.43.03 — эксплойт V67 инлайн в инициализацию драйвера. `sudo ./install.sh --profile=cmp90-rejoin15`. Проверено: персистентный анлок, 9/9 полей FULL.
* **`cmp90hx_pwner`:** Интерактивное меню для Linux: Compute Unlock, PCIe Gen2 (⚠️), P2P, Verify, CUDA toolkit.
* **`cmp90hx` (bendy2):** Исторический первоисточник эксплойта V67 под драйвер 580.159.03 (legacy, systemd-сервис). Содержит `check.sh` + `scripts/rm_issue_rate_query.py` — используется нашим `stack/check.sh`.
* **`cmp50hx-unlock` (xrip):** Решение для Turing CMP 50HX — самый зрелый проект: one-click Linux `.run` **и Windows-инсталлятор с UEFI-анлоком**, проверенный 20GB-мод, динамический WPR2.
* **`nv-uefi-unlocker`:** UEFI-анлок до загрузки ОС для GeForce GTX16–RTX40 (Rust, v2.1.10); CMP в allowlist отсутствует — база для Windows-порта.
* **`nvflashk`, `OMGVflash`:** Инструменты прошивки VBIOS (нужны для 20GB-мода).
* **`MATS_MODS_NVMT`:** Фирменная диагностика памяти (MATS/MODS 400 bootable ISO + nvmt 2.0). Для трека CMP 50HX (TU102); GA102 не поддержан.
* **`455.219`:** Payload MODS/MATS ветки 455 с `gldGA102.bin` — диагностика памяти CMP 90HX, плюс свежий `nvflash`.
* **`MODS - NVMT - Rufus`:** ⭐ Готовый загрузочный USB-образ (Rufus, ≥8 ГБ) с TinyLinux + MODS 455 ×4 сборки + **nvmt 2022 (GA102 = YES)** и скриптами-обёртками — рабочий инструмент валидации памяти 90HX (в т.ч. после 20GB-мода). Первоисточник: [levirepair.eu, thread 3](https://levirepair.eu/infusions/forum/viewthread.php?thread_id=3); MD5 локального образа совпадает с релизом. Разбор всех пакетов: [docs/DIAG_TOOLS_MATS_NVMT.md](docs/DIAG_TOOLS_MATS_NVMT.md).
* **`NVIDIA-patcher`:** Патчер Windows-драйвера 621.01 (NVENC/NvFBC unlock).

---

## 🗺️ Roadmap внедрения

1. ✅ **E — Документация приведена к честным статусам** (этот README, STATUS.md, правки PCIE_AND_P2P.md).
2. ✅ **A — Рабочий Linux-стек**: `stack/install-unlock.sh` + `stack/check.sh` + `stack/bench.sh` + `stack/power.sh`.
3. ✅ **C — Мультикарточная конфигурация**: `stack/p2p-setup.sh` + `stack/run-vllm-tp2.sh` (Qwen 32B на 2×10 ГБ).
4. ⬜ **B — Windows через UEFI**: план в `docs/UEFI_WINDOWS_PLAN.md`; реализация требует портирования EFI-цепочки (GA102) из cmp50hx-unlock.
5. ⬜ **D — 20GB-мод**: процедура в `docs/20GB_PROCEDURE.md`; требует паяльной станции и не проверен на 90HX.
