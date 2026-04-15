#!/bin/bash
# 单点探针 — xinghan-guoxue-72b-v1-2-reason Eagle3 4×H20（调整后参数）
#
# 背景（2026-03-26）：
#   根据 TurboSpec 论文 §4.1.2 Understanding Goodput 的原则：
#   接受率 0.67 时应使用更短的 proposal，减少无效计算。
#   服务端参数已从：--speculative-num-steps 3 --speculative-num-draft-tokens 4
#   调整为：      --speculative-num-steps 2 --speculative-num-draft-tokens 3
#
# 本脚本在 RPS=0.5878（Vanilla 4×H20 ideal_rps）执行单档探测，验证调参效果。
# 与 eagle3-4h20-probe-rps0.5878_20260325_1156（旧参数）对比。
#
# 用法：
#   bash scripts/benchmark/run_guoxue_eagle3_4h20_probe_tuned.sh
#
# 完成后运行分析：
#   PROJECT_DIR/scripts/analysis/analyze_peak_finder.py --phase 2 --dir <OUTPUT_DIR>

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-opti-xinghan-guoxue-p72b-v12-reason/v1/chat/completions"
TARGET_MODEL="infra-opti-xinghan-guoxue-p72b-v12-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_all.csv"
MAX_COMPLETION_TOKENS=4096

# ── 探针参数 ────────────────────────────────────────────────
TARGET_RPS=0.5878
DURATION_SECS=3600    # 1h，与前次探针一致，avg_output_len=2204
NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(${TARGET_RPS} * ${DURATION_SECS} * 1.0))")
# 1h × 0.5878 req/s ≈ 2117 条（与前次 infra-base 探针相同）

# ── 输出目录 ─────────────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%d_%H%M)"
EXP_TAG="eagle3-4h20-probe-tuned-rps0.5878_${TIMESTAMP}"
OUTPUT_DIR="${PROJECT_DIR}/logs/xinghan-guoxue-72b-v1-2-reason/${EXP_TAG}"
LOG_FILE="${PROJECT_DIR}/logs/data-pipeline/${EXP_TAG}.log"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${PROJECT_DIR}/logs/data-pipeline"

RPS_TAG=$(printf "%.4f" "${TARGET_RPS}")

echo "========================================================"
echo "单点探针 — Eagle3 4×H20（调整后：num-steps=2, draft-tokens=3）"
echo "  对比基准：eagle3-4h20-probe-rps0.5878_20260325_1156（旧参数：steps=3, tokens=4）"
echo "  理论依据：TurboSpec §4.1.2 接受率=0.67 → 缩短 proposal 更优"
echo "  端点：   ${SERVER_URL}"
echo "  RPS：    ${TARGET_RPS} req/s"
echo "  时长：   ${DURATION_SECS}s (1h)"
echo "  请求数： ${NUM_REQUESTS}"
echo "  输出：   ${OUTPUT_DIR}"
echo "  日志：   ${LOG_FILE}"
echo "  开始：   $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

START_TIME=$(date +%s)

cd "${LLM_BENCHMARK_ROOT}"

"${PYTHON}" -m llm_benchmark.benchmark.benchmark \
    --exp-name       "guoxue_eagle3_4h20_tuned_probe_rps${RPS_TAG}" \
    --dataset-path   "${DATASET_PATH}" \
    --url            "${SERVER_URL}" \
    --model          "${TARGET_MODEL}" \
    --request-rate   "${TARGET_RPS}" \
    --num-requests   "${NUM_REQUESTS}" \
    --request-time-limit "${DURATION_SECS}" \
    --output-dir     "${OUTPUT_DIR}" \
    --no-kvcache \
    --shuffle \
    --tokenizer      "${TOKENIZER}" \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
    || {
        echo ""
        echo "⚠️  benchmark 异常退出（exit code $?）"
        exit 1
    }

cd "${PROJECT_DIR}"

ELAPSED=$(( $(date +%s) - START_TIME ))
echo ""
echo "✅ 探针完成  耗时 ${ELAPSED}s  结束：$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ── 快速分析 SLA ─────────────────────────────────────────────
echo "── 快速 SLA 分析 ──"
${PYTHON} "${ANALYZE}" \
    --phase 2 \
    --dir "${OUTPUT_DIR}" \
    --ttfs-p90-limit 1.5 \
    --e2e-p90-limit 180.0 \
    2>/dev/null || echo "⚠️  analyze_peak_finder.py 分析失败，请手动运行"

echo ""
echo "── 完整分析（benchmark-result-analysis Skill）──"
echo "  ${PYTHON} scripts/analysis/offline_analysis.py \\"
echo "      --csv ${OUTPUT_DIR}/*.csv \\"
echo "      --output-dir results/${EXP_TAG}/ \\"
echo "      --title 'Eagle3 4×H20 调参后探针 (steps=2, tokens=3)'"
echo ""
echo "输出目录：${OUTPUT_DIR}"
