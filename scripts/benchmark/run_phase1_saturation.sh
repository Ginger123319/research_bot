#!/bin/bash
# Phase 1 饱和探测 — 单档执行脚本（qps-peak-finder）
#
# 用途：以固定并发数（--max-concurrency）压测服务，采集稳态 decode 吞吐。
#       Agent 每次调用此脚本测完一档后，调用 analyze_peak_finder.py 决定下一档并发数。
#
# 必填环境变量：
#   CONCURRENCY      本档并发数（如 10、20、40）；若未设置则回退到 INIT_CONCURRENCY
#   SERVER_URL       服务端点 URL
#   DATASET_PATH     数据集 CSV 路径
#   OUTPUT_BASE_DIR  所有档位的父输出目录（脚本内自动创建子目录 con${CONCURRENCY}/）
#   AVG_OUTPUT_LEN   Phase 0 统计的 avg_output_len（tokens），用于推算 num_requests
#                    ⚠️ 必填：禁止使用 NUM_REQUESTS_MUL×CONCURRENCY 的硬编码方式
#
# 可选环境变量：
#   INIT_CONCURRENCY 先验起始并发数（来自 Grafana active_requests）。
#                    当 CONCURRENCY 未设置时作为起始值使用，可跳过低档位爬坡加速 Phase 1。
#                    详见 qps-peak-finder SKILL.md "执行前：先验并发信息收集" 章节。
#   EST_E2E          先验 E2E 延迟（秒），如有实测值直接传入可跳过公式估算
#   MAX_REQUESTS     num_requests 上限（通常设为数据集行数），防止高并发小模型超出数据集大小
#   TARGET_MODEL     模型名称（默认 ignore-model-name）
#   TOKENIZER        tokenizer 路径（强烈建议提供，否则无法计算 completion_token_cnt）
#   MAX_COMPLETION_TOKENS  最大输出 token 数（默认不限制）
#   TIME_LIMIT_SECS  每档时长（默认 300s）
#
# 用法（标准）：
#   AVG_OUTPUT_LEN=452 CONCURRENCY=20 SERVER_URL=http://... DATASET_PATH=... \
#   OUTPUT_BASE_DIR=logs/mymodel_phase1 bash scripts/benchmark/run_phase1_saturation.sh
#
# 用法（有先验并发数，第一档直接起跳）：
#   AVG_OUTPUT_LEN=452 INIT_CONCURRENCY=60 SERVER_URL=http://... DATASET_PATH=... \
#   OUTPUT_BASE_DIR=logs/mymodel_phase1 bash scripts/benchmark/run_phase1_saturation.sh
#
#   完成后运行分析：
#   .venv/bin/python3 scripts/analysis/analyze_peak_finder.py \
#       --phase 1 --dir logs/mymodel_phase1/con20

set -euo pipefail

# ============================================================
# 参数读取与默认值
# ============================================================
# CONCURRENCY 优先使用显式传入值；否则回退到 INIT_CONCURRENCY（先验起始并发）；均未设置则报错
CONCURRENCY="${CONCURRENCY:-${INIT_CONCURRENCY:-}}"
if [[ -z "${CONCURRENCY}" ]]; then
    echo "❌ 必须设置 CONCURRENCY 或 INIT_CONCURRENCY"
    exit 1
fi
SERVER_URL="${SERVER_URL:?必须设置 SERVER_URL}"
DATASET_PATH="${DATASET_PATH:?必须设置 DATASET_PATH}"
OUTPUT_BASE_DIR="${OUTPUT_BASE_DIR:?必须设置 OUTPUT_BASE_DIR}"

TARGET_MODEL="${TARGET_MODEL:-ignore-model-name}"
TOKENIZER="${TOKENIZER:-}"
MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS:-}"
TIME_LIMIT_SECS="${TIME_LIMIT_SECS:-300}"
AVG_OUTPUT_LEN="${AVG_OUTPUT_LEN:?必须设置 AVG_OUTPUT_LEN（Phase 0 统计值，如 AVG_OUTPUT_LEN=452）}"

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"

LEVEL_DIR="${OUTPUT_BASE_DIR}/con${CONCURRENCY}"
EXP_NAME="phase1_con${CONCURRENCY}"

# NUM_REQUESTS 按 SKILL 公式推算：
#   高并发下单请求实际速率 = 总吞吐 / 并发，远低于单卡峰值；分段估算：
#     avg_out < 100  tokens → 50 t/s/req（4B 快模型）
#     avg_out 100~500 tokens → 20 t/s/req（中等推理）
#     avg_out > 500  tokens → 15 t/s/req（大模型长推理）
#   NUM_REQUESTS = max(CONCURRENCY × ceil(TIME_LIMIT/est_e2e) × 3, CONCURRENCY × 5)
MAX_REQUESTS="${MAX_REQUESTS:-}"

NUM_REQUESTS=$(${PYTHON} -c "
import math, os
avg_out = max(1, ${AVG_OUTPUT_LEN})
known_e2e = float(os.environ.get('EST_E2E', '0'))
if known_e2e > 0:
    est_e2e = known_e2e
elif avg_out < 100:
    est_e2e = max(0.5, avg_out / 50)
elif avg_out < 500:
    est_e2e = max(0.5, avg_out / 20)
else:
    est_e2e = max(0.5, avg_out / 15)
max_comp = ${CONCURRENCY} * math.ceil(${TIME_LIMIT_SECS} / est_e2e)
nr = max(int(max_comp * 3), ${CONCURRENCY} * 5)
max_req = int('${MAX_REQUESTS}') if '${MAX_REQUESTS}' else 0
print(min(nr, max_req) if max_req > 0 else nr)
")

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

mkdir -p "${LEVEL_DIR}"

# ============================================================
# 启动摘要
# ============================================================
echo "========================================================"
echo "Phase 1 饱和探测 — con=${CONCURRENCY}"
echo "========================================================"
echo "  并发数:          ${CONCURRENCY}"
echo "  时长上限:        ${TIME_LIMIT_SECS}s（${TIME_LIMIT_SECS}s = $((TIME_LIMIT_SECS/60))min）"
echo "  avg_output_len:  ${AVG_OUTPUT_LEN} tokens（用于推算 num_requests）"
echo "  请求数上限:      ${NUM_REQUESTS}（按 Phase 0 avg_output_len 公式推算）"
echo "  数据集:          $(basename ${DATASET_PATH})"
echo "  服务 URL:        ${SERVER_URL}"
echo "  输出目录:        ${LEVEL_DIR}"
[[ -n "${TOKENIZER}" ]] && echo "  Tokenizer:       $(basename ${TOKENIZER})" || echo "  Tokenizer:       ⚠️  未设置（completion_token_cnt 将无法计算）"
[[ -n "${MAX_COMPLETION_TOKENS}" ]] && echo "  max_tokens:      ${MAX_COMPLETION_TOKENS}"
echo "  开始时间:        $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

START_TIME=$(date +%s)

# ============================================================
# 构建 benchmark 参数
# ============================================================
BENCH_ARGS=(
    "--exp-name"        "${EXP_NAME}"
    "--dataset-path"    "${DATASET_PATH}"
    "--url"             "${SERVER_URL}"
    "--model"           "${TARGET_MODEL}"
    "--max-concurrency" "${CONCURRENCY}"
    "--num-requests"    "${NUM_REQUESTS}"
    "--request-time-limit" "${TIME_LIMIT_SECS}"
    "--output-dir"      "${LEVEL_DIR}"
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
        echo "⚠️  con=${CONCURRENCY} 执行异常（exit code $?），请检查日志后决定是否继续"
        exit 1
    }

ELAPSED=$(( $(date +%s) - START_TIME ))
echo ""
echo "✅ con=${CONCURRENCY} 完成  耗时 ${ELAPSED}s  结束: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "下一步：运行指标分析"
echo "  ${PYTHON} ${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py \\"
echo "      --phase 1 --dir ${LEVEL_DIR}"
