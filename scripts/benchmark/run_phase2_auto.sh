#!/bin/bash
# Phase 2a 自动收敛循环（两阶段：比例快速逼近 → bracket 几何中点精查）
#
# 阶段 1：无区间时，用比例步进快速逼近边界
# 阶段 2：一旦同时有 pass(LO) 和 fail(HI)，切换到几何中点 sqrt(LO×HI)，
#          bracket 宽度 (HI-LO)/LO < 3% 时收敛
#
# 用法：直接执行，脚本会自动追踪 LO/HI 状态
# 可通过环境变量覆盖初始值：INIT_LO=0.2442 INIT_HI=0.2529 bash run_phase2_auto.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
OUTPUT_BASE="${PROJECT_DIR}/logs/guoxue_phase2_20260318"
CHECKPOINT="${OUTPUT_BASE}/phase2_checkpoint.md"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
PROBE="${PROJECT_DIR}/scripts/benchmark/run_phase2_probe.sh"

SERVER_URL="https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_2026-03-13.csv"
TARGET_MODEL="xinghan-guoxue-72b-v1-2-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
MAX_COMPLETION_TOKENS=4096
DURATION_SECS=1200
PEAK_RPS=0.3707   # Phase 1: 716.9 t/s / 1934 tokens = 0.3707 req/s

# bracket 区间（LO=最高 pass，HI=最低 fail），可从环境变量覆盖
# 根据 Phase 2a 历史数据，已知区间 [0.2494 ✅, 0.2529 ❌]
LO_RPS="${INIT_LO:-0.2494}"
HI_RPS="${INIT_HI:-0.2529}"

echo "========================================================"
echo "Phase 2a 自动收敛  peak_rps=${PEAK_RPS}  duration=${DURATION_SECS}s"
echo "  当前 bracket: LO=${LO_RPS}  HI=${HI_RPS}"
echo "========================================================"

# 起始：从最高已知 pass 档位开始分析
PREV_DIR="${OUTPUT_BASE}/rps0.2369"
CURRENT_DIR="${OUTPUT_BASE}/rps${LO_RPS}"
MAX_ITERS=10

for iter in $(seq 1 ${MAX_ITERS}); do
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 轮  分析: $(basename ${CURRENT_DIR})"
    echo "  bracket: LO=${LO_RPS}  HI=${HI_RPS}"
    echo "────────────────────────────────────────────────────────"

    # 构建 bracket 参数（仅当两者均已知时传入）
    BRACKET_ARGS=""
    if [[ -n "${LO_RPS}" && -n "${HI_RPS}" ]]; then
        BRACKET_ARGS="--bracket-lo ${LO_RPS} --bracket-hi ${HI_RPS}"
    fi

    ANALYSIS_OUT=$(
        ${PYTHON} ${ANALYZE} \
            --phase 2 \
            --dir "${CURRENT_DIR}" \
            ${PREV_DIR:+--prev-dir "${PREV_DIR}"} \
            --ttfs-p90-limit 1.5 \
            --e2e-p90-limit 150.0 \
            --peak-rps ${PEAK_RPS} \
            ${BRACKET_ARGS} \
            --checkpoint "${CHECKPOINT}" \
        2>&1
    )
    echo "${ANALYSIS_OUT}"

    # 从机器可读标记更新 bracket
    CURRENT_RPS=$(basename "${CURRENT_DIR}" | sed 's/rps//')

    if echo "${ANALYSIS_OUT}" | grep -q "\[SLA_PASS\]"; then
        # 更新 LO（取更大值）
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
        # 更新 HI（取更小值）
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

    # 收敛判断（脚本已输出 CONVERGED 标记）
    if echo "${ANALYSIS_OUT}" | grep -q "\[NEXT_RPS=CONVERGED\]"; then
        echo ""
        echo "🎯 Phase 2a 收敛完成！"
        echo "   ideal_rps = ${LO_RPS} req/s  (最高确认通过档)"
        break
    fi

    # 提取 next_rps
    NEXT_RPS=$(echo "${ANALYSIS_OUT}" | grep -oP '\[NEXT_RPS=\K[0-9]+\.[0-9]+' | tail -1)
    if [[ -z "${NEXT_RPS}" ]]; then
        echo "⚠️  无法解析 next_rps，退出"
        break
    fi

    RPS_TAG=$(printf "%.4f" "${NEXT_RPS}")
    NEXT_DIR="${OUTPUT_BASE}/rps${RPS_TAG}"

    # 已跑过则跳过，直接分析
    if [[ -d "${NEXT_DIR}" ]] && ls "${NEXT_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ℹ️  rps=${RPS_TAG} 已有结果，跳过执行直接分析"
        PREV_DIR="${CURRENT_DIR}"
        CURRENT_DIR="${NEXT_DIR}"
        continue
    fi

    echo ""
    echo "  ▶ 执行 rps=${RPS_TAG}  (${DURATION_SECS}s = $((DURATION_SECS/60))min)"
    REQUEST_RATE="${NEXT_RPS}" \
    SERVER_URL="${SERVER_URL}" \
    DATASET_PATH="${DATASET_PATH}" \
    OUTPUT_BASE_DIR="${OUTPUT_BASE}" \
    TARGET_MODEL="${TARGET_MODEL}" \
    TOKENIZER="${TOKENIZER}" \
    MAX_COMPLETION_TOKENS="${MAX_COMPLETION_TOKENS}" \
    DURATION_SECS="${DURATION_SECS}" \
    bash "${PROBE}"

    PREV_DIR="${CURRENT_DIR}"
    CURRENT_DIR="${NEXT_DIR}"
done

echo ""
echo "========================================================"
echo "Phase 2a 完成。bracket=[${LO_RPS}, ${HI_RPS}]  ideal_rps=${LO_RPS}"
echo "检查点: ${CHECKPOINT}"
echo "========================================================"
