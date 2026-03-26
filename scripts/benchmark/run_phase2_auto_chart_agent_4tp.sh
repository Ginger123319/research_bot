#!/bin/bash
# Phase 2a 自动收敛循环 — xinghan-chart-32b-v1-1-agent 4TP（Agent 数据集）
#
# 两阶段：比例快速逼近 → bracket 几何中点精查
# Phase 0 结果: avg_output_len=452 tokens → DURATION=1200s  COOLDOWN=226s
#
# 用法：
#   PEAK_RPS=X.XXXX START_RPS=X.XXXX bash scripts/benchmark/run_phase2_auto_chart_agent_4tp.sh
# 续跑：
#   INIT_LO=X.X INIT_HI=X.X PEAK_RPS=X.XXXX bash scripts/benchmark/run_phase2_auto_chart_agent_4tp.sh

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
PROBE="${PROJECT_DIR}/scripts/benchmark/run_phase2_probe.sh"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-opti-xinghan-chart-p32b-v1-agent/v1/chat/completions"
TARGET_MODEL="/mnt/ai-llm/chartv5"
TOKENIZER="/mnt/ai-llm/chartv5"
DATASET_PATH="${PROJECT_DIR}/datas/output_chart_agent/xinghan-chart-32b-v1-1-agent_all.csv"
MAX_COMPLETION_TOKENS=4096

# ── Phase 0 推算参数（avg_out=452 tokens）──────────────────
DURATION_SECS=1800
COOLDOWN_SECS=226

# ── SLA 阈值 ─────────────────────────────────────────────────
TTFS_P90_LIMIT=1.5    # 1500ms
E2E_P90_LIMIT=150.0   # 150s

# ── Phase 1 输出（由调用方传入）─────────────────────────────
PEAK_RPS="${PEAK_RPS:-0}"

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-4tp-phase2_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase2_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

LO_RPS="${INIT_LO:-}"
HI_RPS="${INIT_HI:-}"
START_RPS="${START_RPS:-}"

if [[ -z "${START_RPS}" && "${PEAK_RPS}" == "0" ]]; then
    echo "❌ 请先完成 Phase 1，然后设置环境变量："
    echo "   PEAK_RPS=<peak_rps>  START_RPS=<max_rps_estimate×1.2>  bash $0"
    exit 1
fi

echo "========================================================"
echo "Phase 2a 自动收敛 — chart-32b-agent 4TP"
echo "  peak_rps=${PEAK_RPS}  start_rps=${START_RPS}"
echo "  duration=${DURATION_SECS}s  cooldown=${COOLDOWN_SECS}s"
echo "  SLA: TTFS≤${TTFS_P90_LIMIT}s  E2E≤${E2E_P90_LIMIT}s"
echo "  bracket: LO=${LO_RPS:-未知}  HI=${HI_RPS:-未知}"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

if [[ -z "${LO_RPS}" && -z "${HI_RPS}" ]]; then
    CURRENT_DIR="${OUTPUT_BASE}/rps$(printf '%.4f' ${START_RPS})"
    PREV_DIR=""
else
    CURRENT_DIR="${OUTPUT_BASE}/rps$(printf '%.4f' ${LO_RPS})"
    PREV_DIR=""
fi

MAX_ITERS=15

for iter in $(seq 1 ${MAX_ITERS}); do
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 轮  当前目录: $(basename ${CURRENT_DIR})"
    echo "  bracket: LO=${LO_RPS:-未知}  HI=${HI_RPS:-未知}"
    echo "────────────────────────────────────────────────────────"

    CURRENT_RPS_TAG=$(basename "${CURRENT_DIR}" | sed 's/rps//')
    if [[ ! -d "${CURRENT_DIR}" ]] || ! ls "${CURRENT_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ▶ 执行 rps=${CURRENT_RPS_TAG}  (${DURATION_SECS}s = $((DURATION_SECS/60))min)"
        REQUEST_RATE="${CURRENT_RPS_TAG}" \
        SERVER_URL="${SERVER_URL}" \
        DATASET_PATH="${DATASET_PATH}" \
        OUTPUT_BASE_DIR="${OUTPUT_BASE}" \
        TARGET_MODEL="${TARGET_MODEL}" \
        TOKENIZER="${TOKENIZER}" \
        MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS}" \
        DURATION_SECS="${DURATION_SECS}" \
        COOLDOWN_SECS="${COOLDOWN_SECS}" \
        bash "${PROBE}"
    else
        echo "  ℹ️  rps=${CURRENT_RPS_TAG} 已有结果，跳过执行直接分析"
    fi

    BRACKET_ARGS=""
    if [[ -n "${LO_RPS}" && -n "${HI_RPS}" ]]; then
        BRACKET_ARGS="--bracket-lo ${LO_RPS} --bracket-hi ${HI_RPS}"
    fi

    ANALYSIS_OUT=$(
        ${PYTHON} ${ANALYZE} \
            --phase 2 \
            --dir "${CURRENT_DIR}" \
            ${PREV_DIR:+--prev-dir "${PREV_DIR}"} \
            --ttfs-p90-limit ${TTFS_P90_LIMIT} \
            --e2e-p90-limit ${E2E_P90_LIMIT} \
            --peak-rps ${PEAK_RPS} \
            ${BRACKET_ARGS} \
            --checkpoint "${CHECKPOINT}" \
        2>&1
    )
    echo "${ANALYSIS_OUT}"

    CURRENT_RPS=$(basename "${CURRENT_DIR}" | sed 's/rps//')

    if echo "${ANALYSIS_OUT}" | grep -q "\[SLA_PASS\]"; then
        if [[ -z "${LO_RPS}" ]]; then
            LO_RPS="${CURRENT_RPS}"
            echo "  📌 bracket LO 初始化: ${LO_RPS}"
        else
            NEW_LO=$(${PYTHON} -c "print('${CURRENT_RPS}' if float('${CURRENT_RPS}') > float('${LO_RPS}') else '${LO_RPS}')")
            if [[ "${NEW_LO}" != "${LO_RPS}" ]]; then
                LO_RPS="${NEW_LO}"
                echo "  📌 bracket LO 更新: ${LO_RPS}"
            fi
        fi
    fi

    if echo "${ANALYSIS_OUT}" | grep -q "\[SLA_FAIL\]"; then
        if [[ -z "${HI_RPS}" ]]; then
            HI_RPS="${CURRENT_RPS}"
            echo "  📌 bracket HI 初始化: ${HI_RPS}"
        else
            NEW_HI=$(${PYTHON} -c "print('${CURRENT_RPS}' if float('${CURRENT_RPS}') < float('${HI_RPS}') else '${HI_RPS}')")
            if [[ "${NEW_HI}" != "${HI_RPS}" ]]; then
                HI_RPS="${NEW_HI}"
                echo "  📌 bracket HI 更新: ${HI_RPS}"
            fi
        fi
    fi

    if [[ -n "${LO_RPS}" && -n "${HI_RPS}" ]]; then
        BRACKET_WIDTH=$(${PYTHON} -c "print(f'{(float(\"${HI_RPS}\")-float(\"${LO_RPS}\"))/float(\"${LO_RPS}\")*100:.1f}')")
        echo "  📐 更新后 bracket: [${LO_RPS}, ${HI_RPS}]  宽度: ${BRACKET_WIDTH}%"
        CONVERGED=$(${PYTHON} -c "print('yes' if (float('${HI_RPS}')-float('${LO_RPS}'))/float('${LO_RPS}') < 0.03 else 'no')")
        if [[ "${CONVERGED}" == "yes" ]]; then
            echo ""
            echo "🎯 Phase 2a 收敛完成！"
            echo "   ideal_rps = ${LO_RPS} req/s"
            echo "   检查点: ${CHECKPOINT}"
            echo ""
            echo "  下一步（Phase 3）启动命令："
            echo "  IDEAL_RPS=${LO_RPS} bash ${PROJECT_DIR}/scripts/benchmark/run_phase3_grid_chart_agent_4tp.sh"
            break
        fi
        NEXT_RPS=$(${PYTHON} -c "import math; print(f'{math.sqrt(float(\"${LO_RPS}\")*float(\"${HI_RPS}\")):.4f}')")
        echo "  → 重算几何中点: sqrt(${LO_RPS} × ${HI_RPS}) = ${NEXT_RPS}"
    else
        if echo "${ANALYSIS_OUT}" | grep -q "\[NEXT_RPS=CONVERGED\]"; then
            if [[ -n "${HI_RPS}" && -n "${LO_RPS}" ]]; then
                WIDTH=$(${PYTHON} -c "print('wide' if (float('${HI_RPS}')-float('${LO_RPS}'))/float('${LO_RPS}') >= 0.03 else 'narrow')")
                if [[ "${WIDTH}" == "wide" ]]; then
                    echo "  ⚠️  analyze 输出 CONVERGED 但 bracket 宽度≥3%，忽略，继续 binary search"
                    NEXT_RPS=$(${PYTHON} -c "import math; print(f'{math.sqrt(float(\"${LO_RPS}\")*float(\"${HI_RPS}\")):.4f}')")
                    echo "  → 重算几何中点: sqrt(${LO_RPS} × ${HI_RPS}) = ${NEXT_RPS}"
                else
                    echo ""
                    echo "🎯 Phase 2a 收敛完成！"
                    echo "   ideal_rps = ${LO_RPS} req/s"
                    echo "   检查点: ${CHECKPOINT}"
                    break
                fi
            else
                echo ""
                echo "🎯 Phase 2a 收敛完成！"
                echo "   ideal_rps = ${LO_RPS} req/s"
                echo "   检查点: ${CHECKPOINT}"
                break
            fi
        else
            NEXT_RPS=$(echo "${ANALYSIS_OUT}" | grep -oP '\[NEXT_RPS=\K[0-9]+\.[0-9]+' | tail -1)
            if [[ -z "${NEXT_RPS}" ]]; then
                echo "⚠️  无法解析 next_rps，退出"
                break
            fi
        fi
    fi

    RPS_TAG=$(printf "%.4f" "${NEXT_RPS}")
    PREV_DIR="${CURRENT_DIR}"
    CURRENT_DIR="${OUTPUT_BASE}/rps${RPS_TAG}"
done

echo ""
echo "========================================================"
echo "Phase 2a 完成。bracket=[${LO_RPS:-?}, ${HI_RPS:-?}]  ideal_rps=${LO_RPS:-?}"
echo "检查点: ${CHECKPOINT}"
echo "========================================================"
