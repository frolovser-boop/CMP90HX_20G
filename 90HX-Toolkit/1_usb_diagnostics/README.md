# 1. USB-диагностика: MODS/MATS 455 + NVMT 2022 (GA102)

## Что получится

Загрузочная флешка с TinyLinux и полным набором диагностики:
**MODS 455** (тесты GPU+памяти, `gldGA102.bin`) + **NVMT 2022** (брингап памяти GA102:
`trainstatus`, тест пинов `g6ca`, ECC/EDC) + скрипты-обёртки с логированием.

## Заливка (один раз)

1. Флешка **≥ 8 ГБ** (данные с неё будут стёрты).
2. Запустить `rufus-3.21.exe` (лежит рядом) → выбрать образ:
   ```
   ../MODS - NVMT - Rufus/MODS From 60GB 1-11-2023 with NVMT.img (вне репозитория, лежит рядом локально)
   ```
   → режим записи **DD** (Rufus предложит сам) → START.
3. (Опционально) сверить образ: MD5 = `3cc2ce1e4b9836548a8fad6479a2c4c3`
   — совпадает с релизом первоисточника.
4. В BIOS/UEFI: **Secure Boot OFF**; загрузка с флешки.

## Использование для CMP 90HX

CMP не имеет видеовыходов → **хост должен быть с iGPU**, монитор — в материнку.

```bash
# после загрузки (root без пароля):
modsinit                      # инициализация secondary-GPU контекста
mods                          # тест GPU+памяти (дефолт: тест 118, fan 60%)
mods -test 275 -pstate 0.max  # полноценный тест памяти
mats -n 1                     # только память карты №1
```

* Логи автоматически сохраняются с датой (`mods455-<дата>.log`) и копируются на
  внешний USB (см. скрипт `/home/mods`, строка `DIR="/media/sdb9/"` — поменять
  под свою флешку по `df -h`).
* Дополнительные аргументы просто дописываются: `mods -loops 10 -test 178 …`.

## Быстрая диагностика памяти GA102 (по опыту треда vlab.su)

⚠️ **Для GDDR6X вердикт даёт MODS, а не MATS** (MATS пропускает дефекты,
«MATS PASS» ≠ исправность). Основные прогоны:

```bash
./mods gputest.js -oqa -skip_rm_state_init -test 94 -fan_speed 70 \
    -dramclk_percent 100 -ignore_fatal_errors -run_on_error   # основной
./mods gputest.js -oqa -old_gold -run_on_error -ignore_fatal_errors \
    -dramclk_percent 110 -fan_speed 80 -test 178              # побайтовый (карта FBIO→чип)
./mods gputest.js -oqa -test 3 -fan_speed 70                  # ловит биты, что 20МБ-MATS пропускает
./mods gputest.js -skip_rm_state_init -notest                 # только инициализация + training status
```

* **TRAINING_STATUS (NV_PFB_FBPA_x_TRAINING_STATUS):** `0x0`=OK; `0x8`=бит чип
  канала (субпартиция 1, напр. A1); `0x2`=проблема со стороны GPU/контактов
  (A0); `0xA`=оба банка. Последние цифры индекса = номер FBPA (90HX: активны
  0,1,2,4,5).
* **Краткие FAILBITS (1–2 бита, напр. D061) = конкретный чип**; чип искать со
  стороны GPU. Свап соседних чипов различает память vs кристалл (ошибки
  остались на том же FBPA → GPU).
* **Ложное, не менять чипы:** ровные 32/64/256 ошибок по всем субпартициям
  (курсор фреймбуфера / UEFI); ошибки по всем 384 битам = training/шина/питание.
* **Питание проверить раньше пайки: VPP 1.8 В GDDR6X обязателен**; FBVDDQ ~30 Ом
  (ниже = КЗ), NVVDD ~0.2 Ом = КЗ кристалла.
* Объём: 10–20 МБ достаточно; весь объём не гнать (ошибки будут всегда).
  Разгон `-dramclk_percent` >105 — только для уже стабильных карт.

Карты «ошибка → физический чип» — в [`../4_memory_maps/`](../4_memory_maps/);
полный полевой справочник — `MyCMP90/docs/MATS_MODS_FIELD_GUIDE.md`.

## NVMT (брингап/пины)

```bash
cd "/home/nvmt_3000_4090/NVMT - 3000-4090"
./mt.sh          # полный прогон с логом mt.log (проверьте nvmt.fid — BDF карты)
./nvmt ts        # training status
./nvmt p         # список устройств
```

## Отключение отказавшего канала (floorsweep, метод Sander/NWR)

```bash
./mods gputest.js -oqa -old_gold -dramclk_percent 100 -fan_speed 50 \
    -run_on_error -ignore_fatal_errors -matsinfo
# + при необходимости: -floorsweep fbio_disable:0xXX:fbp_disable:0xXX
```
Маска = битовая OR: A=0x01 B=0x02 C=0x04 D=0x08 E=0x10 F=0x20 (E+D+A = 0x19).
Внимание: на форуме первоисточника значения записаны с hex/dec-путаницей —
пользуйтесь этой таблицей и проверяйте результат по training status.

## Важно: UEFI vs Legacy (опыт треда vlab.su/buyanigor)

* **Если тест в UEFI показывает мелкие ошибки ПО ВСЕМ каналам сразу** — это
  типичный артефакт UEFI-загрузки, а не битая память. Перегрузитесь в
  **Legacy/CSM** и повторите: в Legacy картина чистая и точечная.
* Битый чип можно искать и в UEFI (если Legacy не грузится), но доверять
  результату — только в Legacy-режиме.
* Полезные аргументы: `-test 95` (быстрый), `-test 275` (память, pstate 0.max),
  `-pstate 0`, `-old_gold`, `-skip_rm_state_init`, `-ignore_fatal_errors`,
  `-run_on_error`.
* Если Rufus не может записать образ (вылет в BusyBox — несовпадение syslinux
  6.03/6.04) — запишите через UltraISO.
* Альтернативные сборки и обсуждение: [vlab.su, тред buyanigor](https://vlab.su/viewtopic.php?t=124090&f=48)
  (там же ссылки MEGA/Яндекс.Диск на MODS 400/455 отдельно).

