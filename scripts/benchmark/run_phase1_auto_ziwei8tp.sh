#!/bin/bash
# Phase 1 自动饱和探测循环 — xinghan-ziwei-32b-v1 8TP（复验）
#
# 从 INIT_CON 开始，每档翻倍或 +10，直至吞吐不再增长（< 1%）。
# 饱和后自动打印 Phase 2 启动参数并直接触发 Phase 2。
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_ziwei8tp.sh
#   INIT_CON=50 bash scripts/benchmark/run_phase1_auto_ziwei8tp.sh  # 断点续跑

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
SATURATE="${PROJECT_DIR}/scripts/benchmark/run_phase1_saturation.sh"
PHASE2_SCRIPT="${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_ziwei8tp.sh"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer-test.geniuworks.com/infra-xinghan-ziwei-p32b-v1-test/v1/chat/completions"
TARGET_MODEL="ignore-model-name"
TOKENIZER="/mnt/ai-llm/xinghan-ziwei-32b-v1"
DATASET_PATH="${PROJECT_DIR}/datas/output_ziwei/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_100_stitched.csv"
MAX_COMPLETION_TOKENS=4096
TIME_LIMIT_SECS=300
NUM_REQUESTS_MUL=200

# ── 初始并发（con=25 已完成，从 con=50 续跑）────────────────
INIT_CON="${INIT_CON:-50}"
TIMESTAMP="20260319"
OUTPUT_BASE="${PROJECT_DIR}/logs/ziwei-32b-8tp-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

echo "========================================================"
echo "Phase 1 自动饱和探测 — ziwei-32b 8TP"
echo "  初始并发: ${INIT_CON}  时长: ${TIME_LIMIT_SECS}s/档"
echo "  服务: ${SERVER_URL}"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
# con=25 已完成，作为首个 PREV_DIR
PREV_DIR="${OUTPUT_BASE}/con25"
MAX_ITERS=12

for iter in $(seq 1 ${MAX_ITERS}); do
    LEVEL_DIR="${OUTPUT_BASE}/con${CURRENT_CON}"

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 档  并发=${CURRENT_CON}"
    echo "────────────────────────────────────────────────────────"

    # 已跑过则跳过，直接分析
    if [[ ! -d "${LEVEL_DIR}" ]] || ! ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        CONCURRENCY="${CURRENT_CON}" \
        SERVER_URL="${SERVER_URL}" \
        DATASET_PATH="${DATASET_PATH}" \
        OUTPUT_BASE_DIR="${OUTPUT_BASE}" \
        TARGET_MODEL="${TARGET_MODEL}" \
        TOKENIZER="${TOKENIZER}" \
        MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS}" \
        TIME_LIMIT_SECS="${TIME_LIMIT_SECS}" \
        NUM_REQUESTS_MUL="${NUM_REQUESTS_MUL}" \
        bash "${SATURATE}"
    else
        echo "  ℹ️  con=${CURRENT_CON} 已有结果，跳过执行直接分析"
    fi

    ANALYSIS_OUT=$(
        ${PYTHON} ${ANALYZE} \
            --phase 1 \
            --dir "${LEVEL_DIR}" \
            ${PREV_DIR:+--prev-dir "${PREV_DIR}"} \
            --checkpoint "${CHECKPOINT}" \
        2>&1
    )
    echo "${ANALYSIS_OUT}"

    NEXT_CON=$(echo "${ANALYSIS_OUT}" | grep -oP '\[NEXT_CON=\K[^\]]+' | tail -1)

    if [[ "${NEXT_CON}" == "SATURATED" ]]; then
        echo ""
        echo "🎯 Phase 1 完成！饱和点已锚定。"
        MAX_RPS=$(echo "${ANALYSIS_OUT}" | grep -oP 'max_rps_estimate\s*=\s*\K[\d.]+' | tail -1)
        START_RPS=$(${PYTHON} -c "print(f'{float(\"${MAX_RPS}\") * 1.2:.4f}')")

        echo ""
        echo "========================================================"
        echo "Phase 1 结果汇总 — ziwei-32b 8TP"
        echo "  max_rps_estimate : ${MAX_RPS} req/s"
        echo "  Phase 2 起始 QPS : ${START_RPS} req/s  (× 1.2)"
        echo "  production_rps   : 1.6667 req/s  (100 RPM / 60)"
        echo "  检查点: ${CHECKPOINT}"
        echo "========================================================"

        echo ""
        echo "▶ 自动启动 Phase 2..."
        PEAK_RPS="${MAX_RPS}" \
        START_RPS="${START_RPS}" \
        bash "${PHASE2_SCRIPT}"
        break
    fi

    if [[ -z "${NEXT_CON}" ]]; then
        echo "⚠️  无法解析 NEXT_CON，退出"
        break
    fi

    PREV_DIR="${LEVEL_DIR}"
    CURRENT_CON="${NEXT_CON}"
done

echo ""
echo "全流程完成。Phase 1 检查点: ${CHECKPOINT}"
