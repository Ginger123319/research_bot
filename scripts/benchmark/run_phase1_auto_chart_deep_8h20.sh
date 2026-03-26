#!/bin/bash
# Phase 1 自动饱和探测循环 — chart-deep-v5-2-235B 8×H20
#
# 从 INIT_CON=60 起跳（Little's Law：1 RPS × 58.8s E2E ≈ 59 并发）
# 预估饱和区并发 60~120，max_rps ≈ 1~1.5 RPS（1 RPS 健康，2 RPS 完全过载）
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_chart_deep_8h20.sh
#   INIT_CON=80 bash scripts/benchmark/run_phase1_auto_chart_deep_8h20.sh  # 从指定并发续跑
#
# Phase 1 结束后按打印的参数执行 Phase 2：
#   PEAK_RPS=X.XXXX START_RPS=X.XXXX bash scripts/benchmark/run_phase2_auto_chart_deep_8h20.sh

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
SATURATE="${PROJECT_DIR}/scripts/benchmark/run_phase1_saturation.sh"

# ── 模型参数 ────────────────────────────────────────────────────
SERVER_URL="http://172.21.65.228:8080/v1/chat/completions"
TARGET_MODEL="ignore-model-name"
TOKENIZER="/mnt/ai-llm/chart/chart_deep/v5-2_235B_chart_deep"
DATASET_PATH="${PROJECT_DIR}/datas/output_chart-deep-v5/combined_extracted.csv"
MAX_COMPLETION_TOKENS=4096
AVG_OUTPUT_LEN=1006      # Phase 0 实测值（old_response tokenize 均值）
EST_E2E=58.8             # 低负载实测 E2E 均值（秒），用于 NUM_REQUESTS 精确推算
TIME_LIMIT_SECS=2520     # max(300, int(1006×2.5))=2515 → 2520s ≈ 42min/档
COOLDOWN_SECS=510        # max(60, int(1006/2))=503 → 510s ≈ 8.5min

# ── 初始并发 ────────────────────────────────────────────────────
INIT_CON="${INIT_CON:-60}"

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/chart-deep-v5-2/chart-deep-v5-2-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

echo "========================================================"
echo "Phase 1 自动饱和探测 — chart-deep-v5-2-235B 8×H20"
echo "  初始并发: ${INIT_CON}"
echo "  时长/档: ${TIME_LIMIT_SECS}s（$(( TIME_LIMIT_SECS/60 ))min）"
echo "  档间冷却: ${COOLDOWN_SECS}s（$(( COOLDOWN_SECS/60 ))min）"
echo "  avg_output_len: ${AVG_OUTPUT_LEN} tokens（Phase 0 实测）"
echo "  est_e2e: ${EST_E2E}s（低负载实测）"
echo "  数据集: $(basename ${DATASET_PATH})"
echo "  服务 URL: ${SERVER_URL}"
echo "  输出目录: ${OUTPUT_BASE}"
echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  ⚠️  注意：每档约 $(( TIME_LIMIT_SECS/60 ))min + $(( COOLDOWN_SECS/60 ))min 冷却"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
PREV_DIR=""
MAX_ITERS=12   # 最多 12 档（每档 ~50min，总时长上限 ~10h）

for iter in $(seq 1 ${MAX_ITERS}); do
    LEVEL_DIR="${OUTPUT_BASE}/con${CURRENT_CON}"

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 档  并发=${CURRENT_CON}  $(date '+%H:%M:%S')"
    echo "────────────────────────────────────────────────────────"

    # 若已有结果则跳过执行
    if [[ ! -d "${LEVEL_DIR}" ]] || ! ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        EST_E2E="${EST_E2E}" \
        CONCURRENCY="${CURRENT_CON}" \
        SERVER_URL="${SERVER_URL}" \
        DATASET_PATH="${DATASET_PATH}" \
        OUTPUT_BASE_DIR="${OUTPUT_BASE}" \
        TARGET_MODEL="${TARGET_MODEL}" \
        TOKENIZER="${TOKENIZER}" \
        MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS}" \
        TIME_LIMIT_SECS="${TIME_LIMIT_SECS}" \
        AVG_OUTPUT_LEN="${AVG_OUTPUT_LEN}" \
        MAX_REQUESTS=5621 \
        bash "${SATURATE}"
    else
        echo "  ℹ️  con=${CURRENT_CON} 已有结果，跳过执行直接分析"
    fi

    # 分析本档结果，获取下一档并发数
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
        echo "Phase 1 结果汇总 — chart-deep-v5-2-235B 8×H20"
        echo "  饱和并发: con=${CURRENT_CON}"
        echo "  max_rps_estimate: ${MAX_RPS:-unknown} req/s"
        if [[ -n "${MAX_RPS:-}" ]]; then
            START_RPS=$(${PYTHON} -c "print(f'{float(\"${MAX_RPS}\") * 1.2:.4f}')")
            echo "  Phase 2 起始 QPS = max_rps × 1.2 = ${START_RPS} req/s"
            echo ""
            echo "  下一步（Phase 2）启动命令："
            echo "  PEAK_RPS=${MAX_RPS} START_RPS=${START_RPS} \\"
            echo "    bash ${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_chart_deep_8h20.sh"
        fi
        echo "  检查点: ${CHECKPOINT}"
        echo "========================================================"

        # 自动触发冷却后启动 Phase 2
        if [[ -n "${AUTO_PHASE2:-}" && -n "${MAX_RPS:-}" ]]; then
            echo ""
            echo "⏳ 冷却 ${COOLDOWN_SECS}s 后自动启动 Phase 2..."
            sleep "${COOLDOWN_SECS}"
            START_RPS=$(${PYTHON} -c "print(f'{float(\"${MAX_RPS}\") * 1.2:.4f}')")
            PEAK_RPS="${MAX_RPS}" START_RPS="${START_RPS}" \
                bash "${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_chart_deep_8h20.sh"
        fi
        break
    fi

    if [[ -z "${NEXT_CON}" ]]; then
        echo "⚠️  无法解析 NEXT_CON，退出"
        break
    fi

    # 档间冷却（防止在途请求污染下档测量）
    echo ""
    echo "  冷却 ${COOLDOWN_SECS}s（$(( COOLDOWN_SECS/60 ))min）..."
    sleep "${COOLDOWN_SECS}"

    PREV_DIR="${LEVEL_DIR}"
    CURRENT_CON="${NEXT_CON}"
done

echo ""
echo "Phase 1 全部档位完成。检查点: ${CHECKPOINT}"
