#!/bin/bash
# Phase 1 自动饱和探测循环 — tianji-querysafety-4b-v2-3 bakv1 4TP
#
# 从初始并发 INIT_CON=9（Grafana max active_requests）起跳，
# 每档翻倍或 +10，直至吞吐不再增长（< 1%）。
# 结束后自动计算 max_rps_estimate，并打印 Phase 2 启动参数。
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_tianji4tp_bakv1.sh
#   INIT_CON=18 bash scripts/benchmark/run_phase1_auto_tianji4tp_bakv1.sh  # 续跑

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
SATURATE="${PROJECT_DIR}/scripts/benchmark/run_phase1_saturation.sh"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23-bakv1/v1/chat/completions"
TARGET_MODEL="/mnt/ai-llm/tianji_query_safety/v2p3_ep1"
TOKENIZER="/mnt/ai-llm/tianji_query_safety/v2p3_ep1"
DATASET_PATH="${PROJECT_DIR}/datas/output_tianji_querysafety/tianji-querysafety-4b-v2-3_peak30min.csv"
MAX_COMPLETION_TOKENS=256
TIME_LIMIT_SECS=300        # 每档 5min
AVG_OUTPUT_LEN=14          # Phase 1 历史实测（tianji safety filter，avg_output=14 tokens）

# ── 初始并发（来自 Grafana max active_requests） ─────────────
INIT_CON="${INIT_CON:-9}"

TIMESTAMP="$(date +%Y%m%d)"
OUTPUT_BASE="${PROJECT_DIR}/logs/tianji-querysafety-bakv1-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

DATASET_DATA_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))

echo "========================================================"
echo "Phase 1 自动饱和探测 — tianji-querysafety-4b-v2-3 bakv1 4TP"
echo "  初始并发: ${INIT_CON}  (Grafana max active_requests)"
echo "  时长: ${TIME_LIMIT_SECS}s/档"
echo "  数据集: $(basename ${DATASET_PATH}) (${DATASET_DATA_ROWS} 条)"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
PREV_DIR=""
MAX_ITERS=15

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
        MAX_REQUESTS="${DATASET_DATA_ROWS}" \
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
        echo "Phase 1 结果汇总 — tianji-querysafety bakv1 4TP"
        echo "  饱和并发: con=${CURRENT_CON}"
        echo "  max_rps_estimate: ${MAX_RPS:-unknown} req/s"
        if [[ -n "${MAX_RPS}" ]]; then
            START_RPS=$(${PYTHON} -c "print(f'{float(\"${MAX_RPS}\") * 1.2:.4f}')")
            echo "  Phase 2 起始 QPS = max_rps × 1.2 = ${START_RPS} req/s"
            echo ""
            echo "  下一步（Phase 2）启动命令："
            echo "  PEAK_RPS=${MAX_RPS} START_RPS=${START_RPS} \\"
            echo "    bash ${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_tianji4tp_bakv1.sh"
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
done

echo ""
echo "Phase 1 全部档位完成。检查点: ${CHECKPOINT}"
