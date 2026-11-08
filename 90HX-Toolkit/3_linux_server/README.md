# 3. Сервер Linux: compute unlock + инференс

Копия скриптов `MyCMP90/stack/` (v. 2026-11-08) — переносится на Linux-сервер
(Ubuntu 20.04/22.04/24.04, Debian 11/12) целиком, `chmod +x *.sh`.

Подробности и полный порядок: `README-stack.md` (рядом) и
`MyCMP90/stack/README.md`. Кратко:

```bash
sudo ./install-unlock.sh        # 1. compute unlock (rejoin15, драйвер 610.43.03)
sudo ./check.sh                 # 2. верификация: 9/9 полей Issue-Rate = full
./bench.sh                      # 3. бенчмарк (LLAMA_MODEL=... ./bench.sh)
sudo ./power.sh 200             # 4. энерголимит 200 Вт (persist — на каждую загрузку)
# ---- для 2+ карт ----
sudo ./p2p-setup.sh             # 5. IOMMU + RegistryDwords → перезагрузка
./p2p-setup.sh verify           # 6. матрица P2P + замер скорости
./run-vllm-tp2.sh               # 7. vLLM TP=2 (Qwen2.5-32B-AWQ) — или PP на Gen1
```

* Требования: Secure Boot OFF, заголовки ядра, интернет.
* Рядом с MyCMP90 на сервере должен лежать репозиторий `cmp90hx-unlock`
  (скрипт найдёт или склонирует сам).
* Статусы методов: `MyCMP90/STATUS.md`. Gen2 PCIe — проверяемая гипотеза
  (маска XVE `0x88FE8`); инференс проектировать из расчёта на Gen1 (PP вместо TP).
