#!/bin/bash
# Phase 3 上线验证网格 — chart-deep-v5-2-235B 8×H20
#
# 在 [PRODUCTION_RPS, IDEAL_RPS] 区间内均匀 4 档验证 SLA 曲线
# 每档 2520s（42min），档间冷却 510s（8.5min）
#
# 用法：
#   IDEAL_RPS=<ideal_rps> bash scripts/benchmark/run_phase3_grid_chart_deep_8h20.sh
#   PRODUCTION_RPS 默认 0.5（30 RPM），可覆盖

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────────
SERVER_URL="http://172.21.65.228:8080/v1/chat/completions"
TARGET_MODEL="ignore-model-name"
TOKENIZER="/mnt/ai-llm/chart/chart_deep/v5-2_235B_chart_deep"
DATASET_PATH="${PROJECT_DIR}/datas/output_chart-deep-v5/combined_extracted.csv"
MAX_COMPLETION_TOKENS=4096
DURATION_SECS=2520     # 与 Phase 2 对齐
COOLDOWN_SECS=510      # 与 Phase 2 对齐

# ── SLA 阈值 ─────────────────────────────────────────────────────
TTFS_P90_LIMIT=1.5
E2E_P90_LIMIT=150.0

# ── Phase 2 输出（由调用方传入）────────────────────────────────────
IDEAL_RPS="${IDEAL_RPS:-}"
PRODUCTION_RPS="${PRODUCTION_RPS:-0.5}"   # 30 RPM 托底

if [[ -z "${IDEAL_RPS}" ]]; then
    echo "❌ 请先完成 Phase 2，然后设置环境变量："
    echo "   IDEAL_RPS=<ideal_rps> bash $0"
    echo "   （PRODUCTION_RPS 默认 0.5，可通过 PRODUCTION_RPS=X 覆盖）"
    exit 1
fi

# ── 计算 4 档 QPS ─────────────────────────────────────────────────
mapfile -t QPS_LEVELS < <(${PYTHON} -c "
import numpy as np
levels = np.linspace(float('${PRODUCTION_RPS}'), float('${IDEAL_RPS}'), 4)
for v in levels:
    print(f'{v:.4f}')
")

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_DIR="${PROJECT_DIR}/logs/chart-deep-v5-2/chart-deep-v5-2-phase3_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

TOTAL_EST_MIN=$(( (${#QPS_LEVELS[@]} * DURATION_SECS + (${#QPS_LEVELS[@]} - 1) * COOLDOWN_SECS) / 60 ))

echo "========================================================"
echo "Phase 3 上线验证网格 — chart-deep-v5-2-235B 8×H20"
echo "  PRODUCTION_RPS=${PRODUCTION_RPS}  IDEAL_RPS=${IDEAL_RPS}"
echo "  SLA: TTFS P90≤${TTFS_P90_LIMIT}s  E2E P90≤${E2E_P90_LIMIT}s"
echo "  档位（4档）: ${QPS_LEVELS[*]}"
echo "  每档时长: ${DURATION_SECS}s（$(( DURATION_SECS/60 ))min），冷却: ${COOLDOWN_SECS}s"
echo "  预计总时长: ~${TOTAL_EST_MIN}min"
echo "  endpoint: ${SERVER_URL}"
echo "  输出目录: ${OUTPUT_DIR}"
echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

START_TIME=$(date +%s)

for i in "${!QPS_LEVELS[@]}"; do
    QPS="${QPS_LEVELS[$i]}"
    LEVEL_NUM=$((i + 1))
    QPS_TAG=$(printf "%.4f" "${QPS}")
    QPS_RPM=$(${PYTHON} -c "print(f'{float(\"${QPS}\")*60:.1f}')")
    LEVEL_DIR="${OUTPUT_DIR}/qps_${QPS_TAG}"
    NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(float('${QPS}') * ${DURATION_SECS} * 1.2))")

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  档位 ${LEVEL_NUM}/${#QPS_LEVELS[@]}  QPS=${QPS} req/s（${QPS_RPM} RPM）"
    echo "  num_requests=${NUM_REQUESTS}  开始: $(date '+%H:%M:%S')"
    echo "────────────────────────────────────────────────────────"

    if [[ -d "${LEVEL_DIR}" ]] && ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ⏭ 已有结果，跳过执行"
    else
        mkdir -p "${LEVEL_DIR}"
        cd "${LLM_BENCHMARK_ROOT}"
        "${PYTHON}" -m llm_benchmark.benchmark.benchmark \
            --exp-name       "chart_deep_v5_2_phase3_qps${QPS_TAG}" \
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

    echo "  完成: $(date '+%H:%M:%S')"

    # 档间冷却（最后一档不等待）
    if [[ $((i + 1)) -lt ${#QPS_LEVELS[@]} ]]; then
        echo "  冷却 ${COOLDOWN_SECS}s..."
        sleep "${COOLDOWN_SECS}"
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "========================================================"
echo "✅ Phase 3 执行完成！"
echo "  总耗时: $((ELAPSED / 3600))h $((ELAPSED % 3600 / 60))min"
echo "  输出目录: ${OUTPUT_DIR}"
echo "========================================================"

# ── Phase 3 快速汇总分析 ───────────────────────────────────────────
echo ""
echo "── Phase 3 SLA 汇总 ─────────────────────────────────────────"
${PYTHON} "${ANALYZE}" \
    --phase 3 \
    --dir "${OUTPUT_DIR}" \
    --ttfs-p90-limit "${TTFS_P90_LIMIT}" \
    --e2e-p90-limit "${E2E_P90_LIMIT}" \
    2>/dev/null || echo "  (分析脚本出错，请手动查看结果目录)"

echo ""
echo "  ▶ 下一步：调用 qps-peak-finder-analysis 技能生成 REPORT.md"
echo "========================================================"
