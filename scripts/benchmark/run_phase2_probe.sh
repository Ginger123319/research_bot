#!/bin/bash
# Phase 2 自适应逼近 — 单档执行脚本（qps-peak-finder）
#
# 用途：以固定 request-rate 压测服务 1200s，采集 SLA 指标和吞吐数据。
#       Agent 每次调用此脚本测完一档后，调用 analyze_peak_finder.py 决定下一档 QPS。
#
# 直接调用 llm_benchmark.benchmark.benchmark（与 Phase 1 保持一致），
# 不经过 bench_llm_benchmark_runner wrapper，避免每档拷贝完整 dataset.csv（175MB+）。
# 结果 CSV 在完成后自动精简（去除 raw_response、messages、old_response 等大列）。
#
# 必填环境变量：
#   REQUEST_RATE     本档 QPS（如 0.15、0.20）
#   SERVER_URL       服务端点 URL
#   DATASET_PATH     数据集 CSV 路径
#   OUTPUT_BASE_DIR  所有档位的父输出目录（脚本内自动创建子目录 rps${REQUEST_RATE}/）
#
# 可选环境变量：
#   TARGET_MODEL           模型名称（默认 ignore-model-name）
#   TOKENIZER              tokenizer 路径（强烈建议提供）
#   MAX_COMPLETION_TOKENS  最大输出 token 数
#   DURATION_SECS          每档时长（默认 1200s）
#   COOLDOWN_SECS          执行完成后等待时间（默认 0，由调用方控制）
#
# 用法：
#   REQUEST_RATE=0.42 SERVER_URL=http://... DATASET_PATH=... OUTPUT_BASE_DIR=logs/mymodel_phase2 \
#   bash scripts/benchmark/run_phase2_probe.sh
#
#   完成后运行分析：
#   .venv/bin/python3 scripts/analysis/analyze_peak_finder.py \
#       --phase 2 --dir logs/mymodel_phase2/rps0.4200 \
#       --prev-dir logs/mymodel_phase2/rps0.3500

set -euo pipefail

# ============================================================
# 参数读取与默认值
# ============================================================
REQUEST_RATE="${REQUEST_RATE:?必须设置 REQUEST_RATE}"
SERVER_URL="${SERVER_URL:?必须设置 SERVER_URL}"
DATASET_PATH="${DATASET_PATH:?必须设置 DATASET_PATH}"
OUTPUT_BASE_DIR="${OUTPUT_BASE_DIR:?必须设置 OUTPUT_BASE_DIR}"

TARGET_MODEL="${TARGET_MODEL:-ignore-model-name}"
TOKENIZER="${TOKENIZER:-}"
MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS:-}"
DURATION_SECS="${DURATION_SECS:-1200}"
COOLDOWN_SECS="${COOLDOWN_SECS:-0}"

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"

# RPS 格式化为目录名（保留 4 位小数）
RPS_TAG=$(printf "%.4f" "${REQUEST_RATE}")
EXP_NAME="phase2_rps${RPS_TAG}"
LEVEL_DIR="${OUTPUT_BASE_DIR}/rps${RPS_TAG}"

# num_requests = ceil(rate × duration)，额外 +20% buffer 保证时间窗口内不提前耗尽
NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(${REQUEST_RATE} * ${DURATION_SECS} * 1.2))")

# ============================================================
# 前置检查
# ============================================================
if [[ ! -f "${DATASET_PATH}" ]]; then
    echo "❌ 数据集不存在: ${DATASET_PATH}"
    exit 1
fi

if [[ ! -f "${PYTHON}" ]]; then
    echo "❌ Python venv 不存在: ${PYTHON}"
    exit 1
fi

DATASET_DATA_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))
if [[ ${NUM_REQUESTS} -gt ${DATASET_DATA_ROWS} ]]; then
    # 数据集不够：缩短有效时长，保证 num_requests ≤ 数据集行数
    # 公式：effective_duration = floor(dataset_rows / (rate * 1.2))
    EFFECTIVE_DURATION=$(python3 -c "import math; print(int(${DATASET_DATA_ROWS} / (${REQUEST_RATE} * 1.2)))")
    if [[ ${EFFECTIVE_DURATION} -lt 300 ]]; then
        echo "❌ 数据集行数 ${DATASET_DATA_ROWS} 不足，有效时长仅 ${EFFECTIVE_DURATION}s（< 300s 最低要求）"
        echo "   请扩充数据集或降低 REQUEST_RATE"
        exit 1
    fi
    echo "⚠️  数据集行数 ${DATASET_DATA_ROWS} < 原始 NUM_REQUESTS=${NUM_REQUESTS}"
    echo "   自适应缩短有效时长: ${DURATION_SECS}s → ${EFFECTIVE_DURATION}s"
    DURATION_SECS="${EFFECTIVE_DURATION}"
    NUM_REQUESTS=$(python3 -c "import math; print(math.ceil(${REQUEST_RATE} * ${DURATION_SECS} * 1.2))")
fi

mkdir -p "${LEVEL_DIR}"

# ============================================================
# 启动摘要
# ============================================================
echo "========================================================"
echo "Phase 2 自适应探测 — rps=${REQUEST_RATE}"
echo "========================================================"
echo "  请求速率:        ${REQUEST_RATE} req/s"
echo "  时长上限:        ${DURATION_SECS}s（$((DURATION_SECS/60))min）"
echo "  请求数上限:      ${NUM_REQUESTS}（= ceil(${REQUEST_RATE} × ${DURATION_SECS} × 1.2)）"
echo "  数据集:          $(basename ${DATASET_PATH})（${DATASET_DATA_ROWS} 条）"
echo "  服务 URL:        ${SERVER_URL}"
echo "  输出目录:        ${LEVEL_DIR}"
[[ -n "${TOKENIZER}" ]] && echo "  Tokenizer:       $(basename ${TOKENIZER})" || echo "  Tokenizer:       ⚠️  未设置（completion_token_cnt 将无法计算）"
[[ -n "${MAX_COMPLETION_TOKENS}" ]] && echo "  max_tokens:      ${MAX_COMPLETION_TOKENS}"
echo "  开始时间:        $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

START_TIME=$(date +%s)

# ============================================================
# 构建 benchmark 参数（直接调用，不经过 wrapper，避免 dataset.csv 拷贝）
# ============================================================
BENCH_ARGS=(
    "--exp-name"          "${EXP_NAME}"
    "--dataset-path"      "${DATASET_PATH}"
    "--url"               "${SERVER_URL}"
    "--model"             "${TARGET_MODEL}"
    "--request-rate"      "${REQUEST_RATE}"
    "--num-requests"      "${NUM_REQUESTS}"
    "--request-time-limit" "${DURATION_SECS}"
    "--output-dir"        "${LEVEL_DIR}"
    "--no-kvcache"
    "--shuffle"
)

[[ -n "${TOKENIZER}" ]]            && BENCH_ARGS+=("--tokenizer" "${TOKENIZER}")
[[ -n "${MAX_COMPLETION_TOKENS}" ]] && BENCH_ARGS+=("--max-completion-tokens" "${MAX_COMPLETION_TOKENS}")

# ============================================================
# 执行
# ============================================================
cd "${LLM_BENCHMARK_ROOT}"

"${PYTHON}" -m llm_benchmark.benchmark.benchmark "${BENCH_ARGS[@]}" \
    || {
        echo ""
        echo "⚠️  rps=${REQUEST_RATE} 执行异常（exit code $?），请检查日志后决定是否继续"
        exit 1
    }

ELAPSED=$(( $(date +%s) - START_TIME ))
echo ""
echo "✅ rps=${REQUEST_RATE} 完成  耗时 ${ELAPSED}s  结束: $(date '+%Y-%m-%d %H:%M:%S')"

if [[ ${COOLDOWN_SECS} -gt 0 ]]; then
    echo "   等待 ${COOLDOWN_SECS}s 冷却..."
    sleep "${COOLDOWN_SECS}"
fi

echo ""
echo "下一步：运行指标分析"
echo "  ${PYTHON} ${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py \\"
echo "      --phase 2 --dir ${LEVEL_DIR} [--prev-dir <上一档目录>]"
