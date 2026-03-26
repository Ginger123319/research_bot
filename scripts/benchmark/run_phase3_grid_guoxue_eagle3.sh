#!/bin/bash
# Phase 3 上线验证网格 — xinghan-guoxue-72b-v1-2-reason EAGLE3
#
# 在 [PRODUCTION_RPS=0.195, IDEAL_RPS] 区间内均匀 4 档验证 SLA 曲线
# 每档 1h，档间冷却 900s（15min）
# production_rps=0.195：线上 20 实例每实例 RPS（集群总 3.9 RPS / 20 = 0.195）
#
# 用法：
#   IDEAL_RPS=<ideal_rps> bash scripts/benchmark/run_phase3_grid_guoxue_eagle3.sh
#   （PRODUCTION_RPS 默认 0.195，可通过环境变量覆盖）

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions"
TARGET_MODEL="xinghan-guoxue-72b-v1-2-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv"
MAX_COMPLETION_TOKENS=4096
DURATION_SECS=3600    # 1h/档（与 Phase 2 对齐）
COOLDOWN_SECS=900     # 15min 冷却

# ── SLA 阈值 ─────────────────────────────────────────────────
TTFS_P90_LIMIT=1.5
E2E_P90_LIMIT=180.0

# ── Phase 2 输出（由调用方传入）────────────────────────────────
IDEAL_RPS="${IDEAL_RPS:-}"
# production_rps = 线上 Grafana 实测每实例 RPS
# 20 实例部署，集群 QPS_base=0.195×20=3.9 req/s
PRODUCTION_RPS="${PRODUCTION_RPS:-0.195}"

if [[ -z "${IDEAL_RPS}" ]]; then
    echo "❌ 请先完成 Phase 2，然后设置环境变量："
    echo "   IDEAL_RPS=<ideal_rps> bash $0"
    echo "   （PRODUCTION_RPS 默认 0.195，可通过 PRODUCTION_RPS=X 覆盖）"
    exit 1
fi

# ── 计算 4 档 QPS ────────────────────────────────────────────
mapfile -t QPS_LEVELS < <(${PYTHON} -c "
import numpy as np
levels = np.linspace(float('${PRODUCTION_RPS}'), float('${IDEAL_RPS}'), 4)
for v in levels:
    print(f'{v:.4f}')
")

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_DIR="${PROJECT_DIR}/logs/guoxue-v2-eagle3-phase3_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

echo "========================================================"
echo "Phase 3 上线验证网格 — guoxue-72b EAGLE3"
echo "  PRODUCTION_RPS=${PRODUCTION_RPS}  IDEAL_RPS=${IDEAL_RPS}"
echo "  SLA: TTFS P90≤${TTFS_P90_LIMIT}s  E2E P90≤${E2E_P90_LIMIT}s"
echo "  档位: ${QPS_LEVELS[*]}"
echo "  每档时长: ${DURATION_SECS}s，档间冷却: ${COOLDOWN_SECS}s"
echo "  预计总时长: $(( ${#QPS_LEVELS[@]} * DURATION_SECS / 3600 ))h $((( ${#QPS_LEVELS[@]} * DURATION_SECS % 3600 ) / 60 ))min（不含冷却）"
echo "  endpoint: ${SERVER_URL}"
echo "  输出目录: ${OUTPUT_DIR}"
echo "========================================================"

START_TIME=$(date +%s)

for i in "${!QPS_LEVELS[@]}"; do
    QPS="${QPS_LEVELS[$i]}"
    LEVEL_NUM=$((i + 1))
    QPS_TAG=$(printf "%.4f" "${QPS}")
    LEVEL_DIR="${OUTPUT_DIR}/qps_${QPS_TAG}"
    NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(float('${QPS}') * ${DURATION_SECS} * 1.2))")

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  档位 ${LEVEL_NUM}/${#QPS_LEVELS[@]}  QPS=${QPS} req/s（$(${PYTHON} -c "print(f'{float(\"${QPS}\")*60:.1f}') ") RPM）"
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  NUM_REQUESTS: ${NUM_REQUESTS}"
    echo "────────────────────────────────────────────────────────"

    if [[ -d "${LEVEL_DIR}" ]] && ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ⏭ 已有结果，跳过执行"
    else
        mkdir -p "${LEVEL_DIR}"
        cd "${LLM_BENCHMARK_ROOT}"
        "${PYTHON}" -m llm_benchmark.benchmark.benchmark \
            --exp-name       "guoxue_eagle3_phase3_qps${QPS_TAG}" \
            --dataset-path   "${DATASET_PATH}" \
            --url            "${SERVER_URL}" \
            --model          "${TARGET_MODEL}" \
            --request-rate   "${QPS}" \
            --num-requests   "${NUM_REQUESTS}" \
            --request-time-limit "${DURATION_SECS}" \
            --output-dir     "${LEVEL_DIR}" \
            --no-kvcache \
            --shuffle \
            --tokenizer      "${TOKENIZER}" \
            --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
            || {
                echo "⚠️ QPS=${QPS} 异常，记录后继续"
                echo "failed_qps=${QPS}" >> "${OUTPUT_DIR}/failed_levels.txt"
            }
        cd "${PROJECT_DIR}"
    fi

    echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')"

    # 档间冷却（最后一档不等待）
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
echo "总耗时: $((ELAPSED / 3600))h $((ELAPSED % 3600 / 60))min"
echo "输出目录: ${OUTPUT_DIR}"
echo "========================================================"

# ── Phase 3 快速汇总分析 ─────────────────────────────────────
echo ""
echo "── Phase 3 SLA 汇总 ────────────────────────────────────"
${PYTHON} "${ANALYZE}" \
    --phase 3 \
    --dir "${OUTPUT_DIR}" \
    --ttfs-p90-limit "${TTFS_P90_LIMIT}" \
    --e2e-p90-limit "${E2E_P90_LIMIT}" \
    2>/dev/null || echo "  (分析脚本出错，请手动查看结果目录)"

echo ""
echo "  ▶ 下一步：调用 qps-peak-finder-analysis 技能生成 REPORT.md"
echo "========================================================"
