# 4. Схемы памяти GA102 / GDDR6X (локализация отказавшего чипа)

Копии вложений треда [levirepair.eu thread 3](https://levirepair.eu/infusions/forum/viewthread.php?thread_id=3)
(авторы: vik-on, f!P[z]y / GerRepair, NWR). Полный набор с пояснениями:
`MyCMP90/docs/img/levirepair/`.

| Схема | Что показывает |
| :--- | :--- |
| `nwr_mem_chart_1.jpg` | **Справочник чипов памяти Micron/Samsung/Hynix** (FBGA-код ↔ скорость ↔ ёмкость) + правило замены: *тот же бренд, та же ёмкость, скорость не ниже*. Для 20GB-мода 90HX: 16 Гбит GDDR6X Micron = **D8BZC (21 Gbps)** / D8BZF; **D8BGW = 8 Гбит** (сток 3080/90HX — не путать!). Дефектные партии: Micron 8Y/8Z хороши, до 49-й нед. 2018 — менять; D8BGX OTT77 термочувствительны; Hynix S2C — реболл свинцом |
| `gddr6_gddr6x_2.jpg` | **Распиновка (pinout) GDDR6 и GDDR6X** — для прозвонки линий и пятаков при реболлинге/20GB-моде |
| `gddr7.png` | Справочник GDDR7 (Blackwell) — для справки |
| `test_memory_ga102.jpg` | **Карта FBPA → физические чипы** (вокруг кристалла: A0/A1, B0/B1, C0/C1, D0/D1, E0/E1, F0/F1) + чтение `NV_PFB_FBPA_N_TRAINING_STATUS` (ненулевой статус = отказ канала; пример: FBPA_2 = 0x0000000B → чип C1; 0xA = 2 чипа в канале). **Для CMP 90HX активны FBPA 0,1,2,4,5 (320 бит) — как на RTX 3080**, карта применима напрямую |
| `gddr6x_x8mode_mapping_frontback.jpg` | Побайтовая карта GDDR6X x8-mode (MODS **test 178**): subpartition 0/1, DRAM1–4, CHA/CHB-байты, top/bottom IC → по байтовым ошибкам вычислить конкретный чип (лицо/тыл платы) |
| `mats_03.png` | Общая раскладка памяти в отчёте MATS |
| `dramtemp.png` | Лог температур DRAM: `./mods gputest.js -test 13 -run_on_error -bg_dram_temp 1000` — аномально горячий чип = неисправный |
| `mods_memory_training.jpg` | Этапы memory training в логе MODS (что должно пройти успешно) |
| `msinvmt.png` | Пример анализа вывода nvmt |

Метод Sander (NWR) для оживления карты с битым каналом и отладки пайки —
[`../1_usb_diagnostics/README.md`](../1_usb_diagnostics/README.md).
