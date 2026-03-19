#!/bin/bash
# Phase 2a 自动收敛循环 — xinghan-chart-32b-v1-1-agent 4TP
#
# 两阶段：比例快速逼近 → bracket 几何中点精查
# 阶段 1：无区间时，用比例步进快速逼近边界
# 阶段 2：一旦同时有 pass(LO) 和 fail(HI)，切换到几何中点 sqrt(LO×HI)，
#          bracket 宽度 (HI-LO)/LO < 3% 时收敛
#
# 用法：直接执行，脚本会自动追踪 LO/HI 状态
# 续跑（从历史中断点恢复）：
#   INIT_LO=X.X INIT_HI=X.X bash scripts/benchmark/run_phase2_auto_chart8tp.sh

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
PROBE="${PROJECT_DIR}/scripts/benchmark/run_phase2_probe.sh"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-opti-xinghan-chart-p32b-v1-agent/v1/chat/completions"
TARGET_MODEL="/mnt/ai-llm/chartv5"
TOKENIZER="/mnt/ai-llm/chartv5"
DATASET_PATH="${PROJECT_DIR}/datas/output_chart/xinghan-chart-32b-v1-1-agent_full.csv"
MAX_COMPLETION_TOKENS=4096
DURATION_SECS=1200
COOLDOWN_SECS=60

# ── SLA 阈值 ─────────────────────────────────────────────────
TTFS_P90_LIMIT=1.5    # 1500ms
E2E_P90_LIMIT=150.0   # 150s

# ── 输出目录（Phase 1 后由 Agent 填入 PEAK_RPS）────────────────
# 留空占位；运行前请先完成 Phase 1 并填入 PEAK_RPS
PEAK_RPS="${PEAK_RPS:-0}"   # Phase 1 完成后由调用方传入，或修改此处默认值

TIMESTAMP="$(date +%Y%m%d)"
OUTPUT_BASE="${PROJECT_DIR}/logs/chart-32b-4tp-phase2_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase2_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

# bracket 区间（可从环境变量覆盖续跑）
LO_RPS="${INIT_LO:-}"
HI_RPS="${INIT_HI:-}"

# Phase 2 起始 QPS（Phase 1 后填入：= max_rps_estimate × 1.2）
START_RPS="${START_RPS:-}"

if [[ -z "${START_RPS}" && "${PEAK_RPS}" == "0" ]]; then
    echo "❌ 请先完成 Phase 1，然后设置环境变量："
    echo "   PEAK_RPS=<peak_rps>  START_RPS=<max_rps_estimate×1.2>  bash $0"
    exit 1
fi

echo "========================================================"
echo "Phase 2a 自动收敛 — chart-32b 4TP"
echo "  peak_rps=${PEAK_RPS}  start_rps=${START_RPS}"
echo "  duration=${DURATION_SECS}s  SLA: TTFS≤${TTFS_P90_LIMIT}s E2E≤${E2E_P90_LIMIT}s"
echo "  bracket: LO=${LO_RPS:-未知}  HI=${HI_RPS:-未知}"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

# 初始化：如果没有 bracket，从 START_RPS 开始第一档
if [[ -z "${LO_RPS}" && -z "${HI_RPS}" ]]; then
    CURRENT_DIR="${OUTPUT_BASE}/rps$(printf '%.4f' ${START_RPS})"
    PREV_DIR=""
else
    # 续跑：从 LO 档位开始分析
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

    # 如果当前目录不存在结果，先运行压测
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

    # 构建 bracket 参数
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

    # 更新 bracket
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

    # bracket 更新后，用最新 LO/HI 重新计算 next_rps（避免 analyze 用旧 bracket 算出陈旧中点）
    if [[ -n "${LO_RPS}" && -n "${HI_RPS}" ]]; then
        BRACKET_WIDTH=$(${PYTHON} -c "print(f'{(float(\"${HI_RPS}\")-float(\"${LO_RPS}\"))/float(\"${LO_RPS}\")*100:.1f}')")
        echo "  📐 更新后 bracket: [${LO_RPS}, ${HI_RPS}]  宽度: ${BRACKET_WIDTH}%"
        CONVERGED=$(${PYTHON} -c "print('yes' if (float('${HI_RPS}')-float('${LO_RPS}'))/float('${LO_RPS}') < 0.03 else 'no')")
        if [[ "${CONVERGED}" == "yes" ]]; then
            echo ""
            echo "🎯 Phase 2a 收敛完成！"
            echo "   ideal_rps = ${LO_RPS} req/s  (最高确认通过档)"
            echo "   检查点: ${CHECKPOINT}"
            break
        fi
        NEXT_RPS=$(${PYTHON} -c "import math; print(f'{math.sqrt(float(\"${LO_RPS}\")*float(\"${HI_RPS}\")):.4f}')")
        echo "  → 重算几何中点: sqrt(${LO_RPS} × ${HI_RPS}) = ${NEXT_RPS}"
    else
        # bracket 不完整（LO 或 HI 缺失）：从 analyze 输出提取
        if echo "${ANALYSIS_OUT}" | grep -q "\[NEXT_RPS=CONVERGED\]"; then
            # 仅当 HI 也未建立时才接受 analyze 的 CONVERGED 判断
            # 若 HI 已建立（bracket 宽度必然 >3%），忽略此判断，继续探测
            if [[ -n "${HI_RPS}" && -n "${LO_RPS}" ]]; then
                WIDTH=$(${PYTHON} -c "print('wide' if (float('${HI_RPS}')-float('${LO_RPS}'))/float('${LO_RPS}') >= 0.03 else 'narrow')")
                if [[ "${WIDTH}" == "wide" ]]; then
                    echo "  ⚠️  analyze 输出 CONVERGED 但 bracket 宽度≥3%，忽略，继续 binary search"
                    NEXT_RPS=$(${PYTHON} -c "import math; print(f'{math.sqrt(float(\"${LO_RPS}\")*float(\"${HI_RPS}\")):.4f}')")
                    echo "  → 重算几何中点: sqrt(${LO_RPS} × ${HI_RPS}) = ${NEXT_RPS}"
                else
                    echo ""
                    echo "🎯 Phase 2a 收敛完成！"
                    echo "   ideal_rps = ${LO_RPS} req/s  (最高确认通过档)"
                    echo "   检查点: ${CHECKPOINT}"
                    break
                fi
            else
                echo ""
                echo "🎯 Phase 2a 收敛完成！"
                echo "   ideal_rps = ${LO_RPS} req/s  (最高确认通过档)"
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
