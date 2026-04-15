#!/bin/bash
# Phase 2a 自动收敛循环 — xinghan-ziwei-32b-v1 8TP（复验）
#
# 两阶段：比例快速逼近 → bracket 几何中点精查
# 用法：Phase 1 完成后直接执行，脚本自动追踪 LO/HI 状态
# 续跑：INIT_LO=X.X INIT_HI=X.X bash scripts/benchmark/run_phase2_auto_ziwei8tp.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
PROBE="${PROJECT_DIR}/scripts/benchmark/run_phase2_probe.sh"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer-test.geniuworks.com/infra-xinghan-ziwei-p32b-v1-test/v1/chat/completions"
TARGET_MODEL="ignore-model-name"
TOKENIZER="/mnt/ai-llm/xinghan-ziwei-32b-v1"
DATASET_PATH="${PROJECT_DIR}/datas/output_ziwei/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_100_stitched.csv"
MAX_COMPLETION_TOKENS=4096
DURATION_SECS=1200
COOLDOWN_SECS=60

# ── SLA 阈值 ─────────────────────────────────────────────────
TTFS_P90_LIMIT=1.5    # 1500ms
E2E_P90_LIMIT=150.0   # 150s

# ── Phase 1 产出填入此处 ──────────────────────────────────────
# PEAK_RPS = max_rps_estimate（Phase 1 checkpoint 中的值）
# START_RPS = PEAK_RPS × 1.2（Phase 2 起始 QPS）
PEAK_RPS="${PEAK_RPS:-0}"
START_RPS="${START_RPS:-}"

TIMESTAMP="$(date +%Y%m%d)"
OUTPUT_BASE="${PROJECT_DIR}/logs/ziwei-32b-8tp-phase2_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase2_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

# bracket 区间（可从环境变量覆盖续跑）
LO_RPS="${INIT_LO:-}"
HI_RPS="${INIT_HI:-}"

if [[ -z "${START_RPS}" && "${PEAK_RPS}" == "0" ]]; then
    echo "❌ 请先完成 Phase 1，然后设置环境变量："
    echo "   PEAK_RPS=<Phase1输出的 max_rps_estimate>"
    echo "   START_RPS=<PEAK_RPS × 1.2>"
    echo "   bash scripts/benchmark/run_phase2_auto_ziwei8tp.sh"
    exit 1
fi

# 若只提供了 PEAK_RPS，自动算 START_RPS
if [[ -z "${START_RPS}" ]]; then
    START_RPS=$(python3 -c "print(f'{float(\"${PEAK_RPS}\")*1.2:.4f}')")
fi

echo "========================================================"
echo "Phase 2a 自动收敛  peak_rps=${PEAK_RPS}  start_rps=${START_RPS}  duration=${DURATION_SECS}s"
echo "  SLA: TTFS P90 ≤ ${TTFS_P90_LIMIT}s  E2E P90 ≤ ${E2E_P90_LIMIT}s"
[[ -n "${LO_RPS}" ]] && echo "  bracket LO=${LO_RPS}" || echo "  bracket LO=未知"
[[ -n "${HI_RPS}" ]] && echo "  bracket HI=${HI_RPS}" || echo "  bracket HI=未知"
echo "========================================================"

# 第一档：从 START_RPS 开始
RPS_TAG=$(printf "%.4f" "${START_RPS}")
CURRENT_DIR="${OUTPUT_BASE}/rps${RPS_TAG}"
PREV_DIR=""
MAX_ITERS=15

for iter in $(seq 1 ${MAX_ITERS}); do
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 轮  目标 rps=$(basename ${CURRENT_DIR} | sed 's/rps//')"
    echo "  bracket: LO=${LO_RPS:-未知}  HI=${HI_RPS:-未知}"
    echo "────────────────────────────────────────────────────────"

    # 已跑过则跳过执行，直接分析
    if [[ ! -d "${CURRENT_DIR}" ]] || ! ls "${CURRENT_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        CURRENT_RPS=$(basename "${CURRENT_DIR}" | sed 's/rps//')
        echo ""
        echo "  ▶ 执行 rps=${CURRENT_RPS}  (${DURATION_SECS}s = $((DURATION_SECS/60))min)"
        REQUEST_RATE="${CURRENT_RPS}" \
        SERVER_URL="${SERVER_URL}" \
        DATASET_PATH="${DATASET_PATH}" \
        OUTPUT_BASE_DIR="${OUTPUT_BASE}" \
        TARGET_MODEL="${TARGET_MODEL}" \
        TOKENIZER="${TOKENIZER}" \
        MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS}" \
        DURATION_SECS="${DURATION_SECS}" \
        bash "${PROBE}"
    else
        echo "  ℹ️  $(basename ${CURRENT_DIR}) 已有结果，跳过执行直接分析"
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

    CURRENT_RPS=$(basename "${CURRENT_DIR}" | sed 's/rps//')

    # 更新 bracket LO（最高通过 RPS）
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

    # 更新 bracket HI（最低失败 RPS）
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

    # 收敛判断
    if echo "${ANALYSIS_OUT}" | grep -q "\[NEXT_RPS=CONVERGED\]"; then
        echo ""
        echo "🎯 Phase 2a 收敛完成！"
        echo "   ideal_rps = ${LO_RPS} req/s  (最高确认通过档)"
        echo "   production_rps = 1.667 req/s  (100 RPM / 60)"
        break
    fi

    # 提取下一档 RPS
    # 若 bracket 已建立，在 shell 层重新计算几何中点（避免复用旧 bracket 的预算值）
    if [[ -n "${LO_RPS}" && -n "${HI_RPS}" ]]; then
        NEXT_RPS=$(${PYTHON} -c "import math; print(f'{math.sqrt(float(\"${LO_RPS}\")*float(\"${HI_RPS}\")):.4f}')")
        CONVERGED=$(${PYTHON} -c "print('yes' if (float('${HI_RPS}')-float('${LO_RPS}'))/float('${LO_RPS}') < 0.03 else 'no')")
        if [[ "${CONVERGED}" == "yes" ]]; then
            echo ""
            echo "🎯 bracket 宽度 < 3%，收敛！ideal_rps = ${LO_RPS} req/s"
            break
        fi
        echo "  📐 bracket 几何中点 next_rps=${NEXT_RPS}（LO=${LO_RPS} HI=${HI_RPS}）"
    else
        # 无 bracket 时 fallback 读取 analyze 的 NEXT_RPS
        NEXT_RPS=$(echo "${ANALYSIS_OUT}" | grep -oP '\[NEXT_RPS=\K[0-9]+\.[0-9]+' | tail -1)
        if [[ -z "${NEXT_RPS}" ]]; then
            echo "⚠️  无法解析 next_rps，退出"
            break
        fi
    fi

    RPS_TAG=$(printf "%.4f" "${NEXT_RPS}")
    PREV_DIR="${CURRENT_DIR}"
    CURRENT_DIR="${OUTPUT_BASE}/rps${RPS_TAG}"

    echo "  ⏱️  冷却 ${COOLDOWN_SECS}s..."
    sleep ${COOLDOWN_SECS}
done

echo ""
echo "========================================================"
echo "Phase 2a 完成。bracket=[${LO_RPS:-未知}, ${HI_RPS:-未知}]  ideal_rps=${LO_RPS:-待确认}"
echo "检查点: ${CHECKPOINT}"
echo "========================================================"
