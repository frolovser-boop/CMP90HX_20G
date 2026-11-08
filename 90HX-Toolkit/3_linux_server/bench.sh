#!/usr/bin/env bash
# =============================================================================
#  MyCMP90 bench — бенчмарки CMP 90HX (compute unlock A/B)
# =============================================================================
#  Что измеряет:
#    1. llama-bench (llama.cpp): pp512 (prefill — чуйствителен к анлоку,
#       должен вырасти ~7-8x) и tg16/tg32 (decode — упирается в ПСП).
#    2. PyTorch GEMM: FP32 и FP16 TFLOPS (прямая проверка скорости ядер).
#
#  Использование:
#    ./bench.sh                                  # только GEMM (torch)
#    LLAMA_MODEL=/path/model.gguf ./bench.sh     # + llama-bench на модели
#    LLAMA_BIN=/path/llama-bench ./bench.sh      # свой бинарь llama-bench
#
#  Результаты дописываются в bench-<дата>.log в каталоге stack/.
#  Совет: прогоните ДО установки анлока и ПОСЛЕ — сравните pp512.
# =============================================================================
set -uo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${STACK_DIR}/bench-$(date +%Y%m%d_%H%M%S).log"
LLAMA_MODEL="${LLAMA_MODEL:-}"
LLAMA_BIN="${LLAMA_BIN:-$(command -v llama-bench || true)}"

log()  { echo "$@" | tee -a "${OUT}"; }

log "MyCMP90 BENCH $(date '+%F %T')"
log "GPU: $(nvidia-smi --query-gpu=name,driver_version,memory.total,clocks.sm --format=csv,noheader 2>/dev/null)"
log "Power: $(nvidia-smi --query-gpu=power.draw,power.limit,temperature.gpu --format=csv,noheader 2>/dev/null)"
log ""

# -----------------------------------------------------------------------------
#  1. PyTorch GEMM (FP32 / FP16 TFLOPS)
# -----------------------------------------------------------------------------
if python3 -c 'import torch' 2>/dev/null; then
    log "=== PyTorch GEMM (8192x8192, 50 итераций) ==="
    python3 - <<'PY' 2>&1 | tee -a "${OUT}"
import torch

for dtype, label in ((torch.float32, "FP32"), (torch.float16, "FP16")):
    a = torch.randn(8192, 8192, device="cuda", dtype=dtype)
    b = torch.randn(8192, 8192, device="cuda", dtype=dtype)
    for _ in range(5):          # прогрев
        c = a @ b
    torch.cuda.synchronize()
    start = torch.cuda.Event(enable_timing=True)
    end = torch.cuda.Event(enable_timing=True)
    start.record()
    for _ in range(50):
        c = a @ b
    end.record()
    torch.cuda.synchronize()
    ms = start.elapsed_time(end) / 50
    tflops = 2 * 8192**3 / (ms / 1000) / 1e12
    print(f"{label}: {tflops:.1f} TFLOPS ({ms:.2f} ms/iter)")
    del a, b, c
    torch.cuda.empty_cache()
PY
else
    log "=== PyTorch не установлен — GEMM пропущен ==="
    log "    (pip install torch --index-url https://download.pytorch.org/whl/cu121)"
fi

# -----------------------------------------------------------------------------
#  2. llama-bench (prefill/decode на LLM)
# -----------------------------------------------------------------------------
if [ -n "${LLAMA_MODEL}" ]; then
    if [ -n "${LLAMA_BIN}" ] && [ -x "${LLAMA_BIN}" ]; then
        log ""
        log "=== llama-bench: $(basename "${LLAMA_MODEL}") ==="
        log "pp512  — prefill, растёт от compute unlock (~7-8x на этом железе)"
        log "tg16/32 — decode, упирается в ПСП памяти (~55 t/s потолок 90HX)"
        "${LLAMA_BIN}" -m "${LLAMA_MODEL}" -p 512 -n 128 -ngl 99 2>&1 | tee -a "${OUT}"
    else
        log ""
        log "=== llama-bench пропущен: бинарь не найден ==="
        log "    Укажите LLAMA_BIN=/path/llama-bench (сборка llama.cpp с -DGGML_CUDA=ON)"
    fi
else
    log ""
    log "=== llama-bench пропущен: LLAMA_MODEL не задан ==="
    log "    Запуск: LLAMA_MODEL=/path/model.gguf ./bench.sh"
fi

log ""
log "Результаты сохранены: ${OUT}"
echo ""
echo -e "Ориентиры (проверенный стек cmp90hx-unlock, gemma-4-12B Q4_0):"
echo -e "  pp512 до анлока:   224.10 t/s"
echo -e "  pp512 после:      1770.67 t/s  (~7.9x)"
echo -e "  tg16 после:         55.48 t/s"
