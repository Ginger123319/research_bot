#!/bin/bash
# Phase 3 上线验证网格 — xinghan-chart-32b-v1-1-agent 8TP
#
# 在 [production_rps, ideal_rps] 区间均匀打 4 档稳态数据
# 用于 qps-sweep-comparison 生成完整 SLA 曲线
#
# 档位（linspace(0.667, 7.6132, 4)）：
#   0.6670 / 2.9824 / 5.2978 / 7.6132 req/s
# 每档时长：2700s（45min）
#
# 用法：bash scripts/benchmark/run_phase3_grid_chart8tp.sh

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-chart-p32b-v1-agent/v1/chat/completions"
TARGET_MODEL="/mnt/ai-llm/chartv5"
TOKENIZER="/mnt/ai-llm/chartv5"
DATASET_PATH="${PROJECT_DIR}/datas/output_chart/xinghan-chart-32b-v1-1-agent_full.csv"
MAX_COMPLETION_TOKENS=4096

# ── 时间控制 ──────────────────────────────────────────────────
DURATION_SECS=2700   # 45min / 档
COOLDOWN_SECS=60

# ── SLA 阈值 ─────────────────────────────────────────────────
TTFS_P90_LIMIT=1.5    # 1500ms
E2E_P90_LIMIT=150.0   # 150s

# ── Phase 3 档位（production_rps=0.667, ideal_rps=7.6132）────
GRID_LEVELS=(0.6670 2.9824 5.2978 7.6132)

TIMESTAMP="$(date +%Y%m%d)"
OUTPUT_BASE="${PROJECT_DIR}/logs/chart-32b-8tp-phase3_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase3_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

DATASET_DATA_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))

echo "========================================================"
echo "Phase 3 上线验证网格 — chart-32b 8TP"
echo "  档位: ${GRID_LEVELS[*]}"
echo "  每档: ${DURATION_SECS}s  冷却: ${COOLDOWN_SECS}s"
echo "  SLA:  TTFS P90 ≤ ${TTFS_P90_LIMIT}s  E2E P90 ≤ ${E2E_P90_LIMIT}s"
echo "  数据集: $(basename ${DATASET_PATH})（${DATASET_DATA_ROWS} 条）"
echo "  输出: ${OUTPUT_BASE}"
echo "========================================================"

for QPS in "${GRID_LEVELS[@]}"; do
    QPS_TAG=$(printf "%.4f" "${QPS}")
    EXP_NAME="phase3_qps${QPS_TAG}"
    LEVEL_DIR="${OUTPUT_BASE}/qps${QPS_TAG}"
    mkdir -p "${LEVEL_DIR}"

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  档位: qps=${QPS_TAG}  时长: ${DURATION_SECS}s = $((DURATION_SECS/60))min"
    echo "────────────────────────────────────────────────────────"

    if ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ℹ️  已有结果，跳过执行直接分析"
    else
        # 计算请求数，数据集不足时自适应缩短时长
        NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(${QPS} * ${DURATION_SECS} * 1.2))")
        ACTUAL_DURATION=${DURATION_SECS}
        if [[ ${NUM_REQUESTS} -gt ${DATASET_DATA_ROWS} ]]; then
            ACTUAL_DURATION=$(python3 -c "import math; print(int(${DATASET_DATA_ROWS} / (${QPS} * 1.2)))")
            NUM_REQUESTS=$(python3 -c "import math; print(math.ceil(${QPS} * ${ACTUAL_DURATION} * 1.2))")
            echo "  ⚠️  数据集行数 ${DATASET_DATA_ROWS} 不足，时长自适应: ${DURATION_SECS}s → ${ACTUAL_DURATION}s"
        fi
        echo "  ▶ 发送 ${NUM_REQUESTS} 条请求（${ACTUAL_DURATION}s）"

        START_TIME=$(date +%s)

        cd "${LLM_BENCHMARK_ROOT}"
        BENCH_ARGS=(
            "--exp-name"          "${EXP_NAME}"
            "--dataset-path"      "${DATASET_PATH}"
            "--url"               "${SERVER_URL}"
            "--model"             "${TARGET_MODEL}"
            "--request-rate"      "${QPS}"
            "--num-requests"      "${NUM_REQUESTS}"
            "--request-time-limit" "${ACTUAL_DURATION}"
            "--output-dir"        "${LEVEL_DIR}"
            "--tokenizer"         "${TOKENIZER}"
            "--max-completion-tokens" "${MAX_COMPLETION_TOKENS}"
            "--no-kvcache"
            "--shuffle"
        )

        "${PYTHON}" -m llm_benchmark.benchmark.benchmark "${BENCH_ARGS[@]}" \
            || echo "  ⚠️  qps=${QPS_TAG} 执行异常，继续下一档"

        cd "${PROJECT_DIR}"
        ELAPSED=$(( $(date +%s) - START_TIME ))
        echo "  ✅ qps=${QPS_TAG} 完成  耗时 ${ELAPSED}s"
    fi

    echo ""
    echo "  ── 分析 qps=${QPS_TAG} ──"
    ${PYTHON} ${ANALYZE} \
        --phase 3 \
        --dir "${LEVEL_DIR}" \
        --ttfs-p90-limit ${TTFS_P90_LIMIT} \
        --e2e-p90-limit ${E2E_P90_LIMIT} \
        --checkpoint "${CHECKPOINT}" \
        2>&1 || echo "  ⚠️  分析失败，继续下一档"

    if [[ "${QPS}" != "${GRID_LEVELS[-1]}" ]]; then
        echo "  💤 冷却 ${COOLDOWN_SECS}s ..."
        sleep "${COOLDOWN_SECS}"
    fi
done

echo ""
echo "========================================================"
echo "Phase 3 完成！"
echo "  输出目录: ${OUTPUT_BASE}"
echo "  检查点:   ${CHECKPOINT}"
echo ""
echo "下一步：用 qps-sweep-comparison Skill 生成图表"
echo "========================================================"
