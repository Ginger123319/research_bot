#!/bin/bash
# Phase 3 上线验证网格 — xinghan-guoxue-72b-v1-2-reason
# 在开区间 (0.195, 0.2481) 内均匀 4 档验证 SLA 曲线

set -euo pipefail

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"

# ============================================================
# 模型配置
# ============================================================
TARGET_MODEL="xinghan-guoxue-72b-v1-2-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
SERVER_URL="https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_2026-03-13.csv"
MAX_COMPLETION_TOKENS=4096

# ============================================================
# Phase 3 档位（开区间 0.195 < QPS < 0.2481）
# ============================================================
QPS_LEVELS=(0.2056 0.2162 0.2269 0.2375)
DURATION_SECS=2700  # 45min/档
COOLDOWN_SECS=90

# ============================================================
# 输出目录
# ============================================================
TIMESTAMP=$(date +%Y%m%d)
OUTPUT_DIR="${PROJECT_DIR}/logs/guoxue_phase3_grid_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

echo "========================================================"
echo "Phase 3 上线验证网格 — guoxue-72b"
echo "========================================================"
echo "档位数: ${#QPS_LEVELS[@]}"
echo "每档时长: ${DURATION_SECS}s ($(($DURATION_SECS/60))min)"
echo "总预计时长: $((${#QPS_LEVELS[@]} * ($DURATION_SECS + $COOLDOWN_SECS) / 60))min"
echo "输出目录: ${OUTPUT_DIR}"
echo "========================================================"
echo ""

START_TIME=$(date +%s)

for i in "${!QPS_LEVELS[@]}"; do
    QPS="${QPS_LEVELS[$i]}"
    LEVEL_NUM=$((i + 1))
    
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  档位 ${LEVEL_NUM}/${#QPS_LEVELS[@]}  QPS=${QPS} req/s"
    echo "────────────────────────────────────────────────────────"
    
    QPS_TAG=$(printf "%.4f" "${QPS}")
    EXP_NAME="phase3_qps${QPS_TAG}"
    LEVEL_DIR="${OUTPUT_DIR}/qps_${QPS_TAG}"
    mkdir -p "${LEVEL_DIR}"
    
    # 计算 NUM_REQUESTS（QPS × 时长 × 1.2 buffer）
    NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(${QPS} * ${DURATION_SECS} * 1.2))")
    
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  NUM_REQUESTS: ${NUM_REQUESTS}"
    echo "  输出目录: ${LEVEL_DIR}"
    
    # 构建 benchmark 参数
    BENCH_ARGS=(
        "--exp-name"          "${EXP_NAME}"
        "--dataset-path"      "${DATASET_PATH}"
        "--url"               "${SERVER_URL}"
        "--model"             "${TARGET_MODEL}"
        "--request-rate"      "${QPS}"
        "--num-requests"      "${NUM_REQUESTS}"
        "--request-time-limit" "${DURATION_SECS}"
        "--output-dir"        "${LEVEL_DIR}"
        "--no-kvcache"
        "--shuffle"
        "--tokenizer"         "${TOKENIZER}"
        "--max-completion-tokens" "${MAX_COMPLETION_TOKENS}"
    )
    
    # 执行 benchmark
    cd "${LLM_BENCHMARK_ROOT}"
    
    "${PYTHON}" -m llm_benchmark.benchmark.benchmark "${BENCH_ARGS[@]}" \
        || {
            echo "⚠️ 档位 QPS=${QPS} 异常，记录后继续"
            echo "failed_qps=${QPS}" >> "${OUTPUT_DIR}/failed_levels.txt"
        }
    
    echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 冷却
    if [[ $((i + 1)) -lt ${#QPS_LEVELS[@]} ]]; then
        echo "  冷却 ${COOLDOWN_SECS}s..."
        sleep ${COOLDOWN_SECS}
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "========================================================"
echo "✅ Phase 3 执行完成！"
echo "========================================================"
echo "总耗时: $((ELAPSED / 3600))h $((ELAPSED % 3600 / 60))min"
echo "输出目录: ${OUTPUT_DIR}"
echo "========================================================"
