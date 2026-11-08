#!/usr/bin/env bash
# =============================================================================
#  MyCMP90 run-vllm-tp2 — LLM-сервер на 2×CMP 90HX (Tensor Parallelism)
# =============================================================================
#  Запускает vLLM OpenAI-совместимый сервер на 2 картах 10 ГБ:
#    Qwen2.5-32B-Instruct-AWQ (Q4, ~18.5 ГБ весов) с TP=2.
#
#  Использование:
#    ./run-vllm-tp2.sh                       # Qwen2.5-32B-AWQ, порт 8000
#    MODEL=Qwen/Qwen2.5-14B-Instruct-AWQ ./run-vllm-tp2.sh   # своя модель
#    MAXLEN=16384 ./run-vllm-tp2.sh          # свой контекст
#
#  Требования:
#    - compute unlock активен (stack/check.sh PASS)
#    - P2P включён (stack/p2p-setup.sh verify) — иначе AllReduce пойдёт через RAM
#    - pip install vllm (версия с поддержкой вашей CUDA)
#  Статус: ⬜ теория из INFERENCE_GUIDE.md — первый запуск заодно проверит её.
# =============================================================================
set -euo pipefail

MODEL="${MODEL:-Qwen/Qwen2.5-32B-Instruct-AWQ}"
QUANT="${QUANT:-awq}"
PORT="${PORT:-8000}"
MAXLEN="${MAXLEN:-8192}"
MEMUTIL="${MEMUTIL:-0.90}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
else
    CYAN=""; GREEN=""; RED=""; NC=""
fi
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC}  $*"; }
err()  { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# --- предпроверки -------------------------------------------------------------
command -v nvidia-smi >/dev/null 2>&1 || err "nvidia-smi недоступен"
NGPU="$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)"
[ "${NGPU}" -ge 2 ] || err "Найдено ${NGPU} GPU — для TP=2 нужно минимум 2 (обе карты должны быть видимы драйверу)"

python3 -c 'import vllm' 2>/dev/null || err "vLLM не установлен: pip install vllm"

# Только CMP 90HX в CUDA_VISIBLE_DEVICES (по порядку PCI)
CVD="$(python3 - <<'PY'
import subprocess
out = subprocess.check_output(["nvidia-smi", "--query-gpu=index,pci.bus_id", "--format=csv,noheader"], text=True)
cmp90 = []
bdfs = subprocess.run(["bash", "-c",
    "for d in /sys/bus/pci/devices/*; do "
    "[ \"$(cat $d/vendor 2>/dev/null)\" = 0x10de ] && "
    "[ \"$(cat $d/device 2>/dev/null)\" = 0x220d ] && basename $d; done"],
    capture_output=True, text=True).stdout.split()
rows = []
for line in out.strip().splitlines():
    idx, bus = [x.strip() for x in line.split(",")]
    rows.append((int(idx), bus.replace("00000000:", "").replace("0000:", "").upper()))
for idx, bus in sorted(rows, key=lambda r: r[1]):
    if any(b.replace("0000:", "").upper() in bus for b in bdfs):
        cmp90.append(idx)
print(",".join(map(str, cmp90)) if cmp90 else "")
PY
)"
[ -n "${CVD}" ] || err "Не нашёл ни одной CMP 90HX среди GPU"
ok "CUDA_VISIBLE_DEVICES=${CVD} (${MODEL}, TP=2, порт ${PORT})"

# --- запуск -------------------------------------------------------------------
info "Первый запуск скачает веса (~18-20 ГБ) — по PCIe Gen1 это 1-2 часа, наберитесь терпения."
info "Остановить: Ctrl+C. Тест: curl http://localhost:${PORT}/v1/models"
echo ""
export CUDA_VISIBLE_DEVICES="${CVD}"
exec python3 -m vllm.entrypoints.openai.api_server \
    --model "${MODEL}" \
    --quantization "${QUANT}" \
    --tensor-parallel-size 2 \
    --dtype float16 \
    --gpu-memory-utilization "${MEMUTIL}" \
    --max-model-len "${MAXLEN}" \
    --port "${PORT}"
