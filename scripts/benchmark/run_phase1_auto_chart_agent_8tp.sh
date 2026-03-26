#!/bin/bash
# Phase 1 自动饱和探测循环 — xinghan-chart-32b-v1-1-agent 8TP（Agent 数据集）
#
# 数据集: datas/output_chart_agent/_all.csv（40,311 条 Agent 调用，avg_out=452 tokens）
# Phase 0 结果: avg_output_len=452 tokens → TIME_LIMIT=1130s  COOLDOWN=226s
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_chart_agent_8tp.sh
#   INIT_CON=100 bash scripts/benchmark/run_phase1_auto_chart_agent_8tp.sh  # 从指定并发续跑
#
# Phase 1 结束后，按打印的参数执行：
#   PEAK_RPS=X.XXXX START_RPS=X.XXXX bash scripts/benchmark/run_phase2_auto_chart_agent_8tp.sh

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
SATURATE="${PROJECT_DIR}/scripts/benchmark/run_phase1_saturation.sh"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-chart-p32b-v1-agent/v1/chat/completions"
TARGET_MODEL="/mnt/ai-llm/chartv5"
TOKENIZER="/mnt/ai-llm/chartv5"
DATASET_PATH="${PROJECT_DIR}/datas/output_chart_agent/xinghan-chart-32b-v1-1-agent_all.csv"
MAX_COMPLETION_TOKENS=4096

# ── Phase 0 推算参数（avg_out=452 tokens）──────────────────
# TIME_LIMIT = max(300, int(452 * 2.5)) = 1130s
# COOLDOWN   = max(60,  int(452 / 2))   = 226s
TIME_LIMIT_SECS=1130
COOLDOWN_SECS=226
AVG_OUTPUT_LEN=452     # Phase 0 实测（old_response tokenize 统计）

# ── 初始并发（Phase 0 建议：从 con=50 起跳）──────────────────
INIT_CON="${INIT_CON:-50}"

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-8tp-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

echo "========================================================"
echo "Phase 1 自动饱和探测 — chart-32b-agent 8TP"
echo "  初始并发: ${INIT_CON}  时长: ${TIME_LIMIT_SECS}s/档  冷却: ${COOLDOWN_SECS}s"
echo "  数据集: $(basename ${DATASET_PATH})"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
PREV_DIR=""
MAX_ITERS=12

for iter in $(seq 1 ${MAX_ITERS}); do
    LEVEL_DIR="${OUTPUT_BASE}/con${CURRENT_CON}"

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 档  并发=${CURRENT_CON}"
    echo "────────────────────────────────────────────────────────"

    if [[ ! -d "${LEVEL_DIR}" ]] || ! ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        CONCURRENCY="${CURRENT_CON}" \
        SERVER_URL="${SERVER_URL}" \
        DATASET_PATH="${DATASET_PATH}" \
        OUTPUT_BASE_DIR="${OUTPUT_BASE}" \
        TARGET_MODEL="${TARGET_MODEL}" \
        TOKENIZER="${TOKENIZER}" \
        MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS}" \
        TIME_LIMIT_SECS="${TIME_LIMIT_SECS}" \
        AVG_OUTPUT_LEN="${AVG_OUTPUT_LEN}" \
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
            --avg-output-len-phase0 "${AVG_OUTPUT_LEN}" \
        2>&1
    )
    echo "${ANALYSIS_OUT}"

    NEXT_CON=$(echo "${ANALYSIS_OUT}" | grep -oP '\[NEXT_CON=\K[^\]]+' | tail -1)

    if [[ "${NEXT_CON}" == "SATURATED" ]]; then
        echo ""
        echo "🎯 Phase 1 完成！已探测到饱和点。"
        MAX_RPS=$(echo "${ANALYSIS_OUT}" | grep -oP 'max_rps_estimate\s*=\s*\K[\d.]+' | tail -1)
        echo ""
        echo "========================================================"
        echo "Phase 1 结果汇总 — chart-32b-agent 8TP"
        echo "  最大吞吐并发: con=${CURRENT_CON}"
        echo "  max_rps_estimate: ${MAX_RPS:-unknown} req/s"
        if [[ -n "${MAX_RPS}" ]]; then
            START_RPS=$(${PYTHON} -c "print(f'{float(\"${MAX_RPS}\") * 1.2:.4f}')")
            echo "  Phase 2 起始 QPS = max_rps × 1.2 = ${START_RPS} req/s"
            echo ""
            echo "  下一步（Phase 2）启动命令："
            echo "  PEAK_RPS=${MAX_RPS} START_RPS=${START_RPS} \\"
            echo "    bash ${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_chart_agent_8tp.sh"
        fi
        echo "  检查点: ${CHECKPOINT}"
        echo "========================================================"
        break
    fi

    if [[ -z "${NEXT_CON}" ]]; then
        echo "⚠️  无法解析 NEXT_CON，退出"
        break
    fi

    PREV_DIR="${LEVEL_DIR}"
    CURRENT_CON="${NEXT_CON}"

    echo "  💤 冷却 ${COOLDOWN_SECS}s ..."
    sleep "${COOLDOWN_SECS}"
done

echo ""
echo "Phase 1 全部档位完成。检查点: ${CHECKPOINT}"
