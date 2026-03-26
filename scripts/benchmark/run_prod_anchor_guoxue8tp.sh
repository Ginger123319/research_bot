#!/bin/bash
# 生产锚点补测 — xinghan-guoxue-72b-v1-2-reason 8×L20
#
# 在真实生产工作点 0.195 req/s（Grafana 实测单实例 RPS）补跑 1h，
# 用于 Phase 3 REPORT.md 的"生产 RPM 锚点"行。
#
# 用法：
#   bash scripts/benchmark/run_prod_anchor_guoxue8tp.sh

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

SERVER_URL="https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions"
TARGET_MODEL="xinghan-guoxue-72b-v1-2-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv"
MAX_COMPLETION_TOKENS=4096

PROD_RPS="0.1950"           # Grafana 实测单实例 RPS
DURATION_SECS=3600           # 1h（与 Phase 3 其他档一致）
TTFS_P90_LIMIT=1.5
E2E_P90_LIMIT=180.0

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/guoxue-v2-8tp-prod-anchor_${TIMESTAMP}"
QPS_TAG=$(printf "%.4f" "${PROD_RPS}")
LEVEL_DIR="${OUTPUT_DIR}/qps_${QPS_TAG}"
NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(float('${PROD_RPS}') * ${DURATION_SECS} * 1.2))")

mkdir -p "${LEVEL_DIR}"

echo "========================================================"
echo "生产锚点补测 — guoxue-72b 8×L20"
echo "  QPS          = ${PROD_RPS} req/s（${QPS_TAG} → $(python3 -c "print(f'{float(\"${PROD_RPS}\")*60:.1f}')")  RPM/实例）"
echo "  时长         = ${DURATION_SECS}s (1h)"
echo "  NUM_REQUESTS = ${NUM_REQUESTS}"
echo "  SLA: TTFS P90≤${TTFS_P90_LIMIT}s  E2E P90≤${E2E_P90_LIMIT}s"
echo "  输出目录     = ${OUTPUT_DIR}"
echo "  预计完成     = $(date -d "+${DURATION_SECS} seconds" '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

cd "${LLM_BENCHMARK_ROOT}"
"${PYTHON}" -m llm_benchmark.benchmark.benchmark \
    --exp-name       "guoxue_v2_8tp_prod_anchor_${QPS_TAG}" \
    --dataset-path   "${DATASET_PATH}" \
    --url            "${SERVER_URL}" \
    --model          "${TARGET_MODEL}" \
    --request-rate   "${PROD_RPS}" \
    --num-requests   "${NUM_REQUESTS}" \
    --request-time-limit "${DURATION_SECS}" \
    --output-dir     "${LEVEL_DIR}" \
    --no-kvcache \
    --shuffle \
    --tokenizer      "${TOKENIZER}" \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}"
cd "${PROJECT_DIR}"

echo ""
echo "========================================================"
echo "✅ 生产锚点补测完成！"
echo "========================================================"

# 快速 SLA 分析
echo "── SLA 分析 ────────────────────────────────────────────"
${PYTHON} "${ANALYZE}" \
    --phase 3 \
    --dir "${OUTPUT_DIR}" \
    --ttfs-p90-limit "${TTFS_P90_LIMIT}" \
    --e2e-p90-limit "${E2E_P90_LIMIT}" \
    2>/dev/null || true

echo ""
echo "  ▶ 下一步：将结果补录到"
echo "    results/guoxue-v2-8tp-peak-finder-20260323/REPORT.md §3 Phase 3 表格"
echo "========================================================"
