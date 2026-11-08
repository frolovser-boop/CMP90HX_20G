# stack/ — готовые скрипты MyCMP90

Порядок внедрения на Linux-хосте (Ubuntu 20.04/22.04/24.04, Debian 11/12):

```bash
# 1. Установка compute unlock (rejoin15, драйвер 610.43.03) — один раз
sudo ./install-unlock.sh                # --preflight для проверки окружения

# 2. Верификация анлока (после каждой перезагрузки — по желанию)
sudo ./check.sh

# 3. Бенчмарки (до/после анлока, GEMM + опционально llama-bench)
./bench.sh
LLAMA_MODEL=/path/model.gguf ./bench.sh

# 4. Энерголимит (рекомендуется: 200 Вт ≈ 96% производительности)
sudo ./power.sh 200
sudo ./power.sh persist 200             # + автоприменение при загрузке

# ---- далее только для 2+ карт ----

# 5. P2P между картами
sudo ./p2p-setup.sh                     # настроить GRUB + modprobe.d, перезагрузка
./p2p-setup.sh verify                   # матрица P2P + замер скорости

# 6. LLM-сервер на 2 картах (Qwen2.5-32B-AWQ, TP=2)
./run-vllm-tp2.sh
```

Переменные окружения: `CMP90HX_HOME` — каталог с соседними репозиториями
(по умолчанию — родитель MyCMP90), `RM_QUERY` — путь к
`rm_issue_rate_query.py` (ищется в `../cmp90hx`, иначе скачивается).

Статус каждого метода и ограничения — в [`../STATUS.md`](../STATUS.md).
Скрипты предполагают Secure Boot **выключенным** и EFI-загрузку x86_64.
