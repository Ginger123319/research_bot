#!/bin/bash
# Phase 3 上线验证网格 — xinghan-chart-32b-v1-1-agent 4TP（Agent 数据集）
#
# 在 [production_rps, ideal_rps] 区间均匀打 4 档稳态数据
# Phase 0 结果: avg_output_len=452 tokens → DURATION=1200s  COOLDOWN=226s
# production_rps = 118 RPM / 60 = 1.967 req/s（Grafana 生产峰值）
#
# 必填环境变量：
#   IDEAL_RPS  Phase 2 输出的 ideal_rps
#
# 用法：
#   IDEAL_RPS=X.XX bash scripts/benchmark/run_phase3_grid_chart_agent_4tp.sh

set -uo pipefail

IDEAL_RPS="${IDEAL_RPS:?必须设置 IDEAL_RPS（来自 Phase 2 输出）}"
PRODUCTION_RPS="1.967"    # 118 RPM / 60

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"

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

# ── 计算 4 档 linspace(production_rps, ideal_rps, 4) ────────
readarray -t GRID_LEVELS < <(${PYTHON} -c "
import numpy as np
pts = np.linspace(${PRODUCTION_RPS}, ${IDEAL_RPS}, 4)
for p in pts:
    print(f'{p:.4f}')
")

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-4tp-phase3_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase3_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

DATASET_DATA_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))

echo "========================================================"
echo "Phase 3 上线验证网格 — chart-32b-agent 4TP"
echo "  production_rps = ${PRODUCTION_RPS}  ideal_rps = ${IDEAL_RPS}"
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
        NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(${QPS} * ${DURATION_SECS} * 1.2))")
        ACTUAL_DURATION=${DURATION_SECS}
        if [[ ${NUM_REQUESTS} -gt ${DATASET_DATA_ROWS} ]]; then
            ACTUAL_DURATION=$(${PYTHON} -c "import math; print(int(${DATASET_DATA_ROWS} / (${QPS} * 1.2)))")
            NUM_REQUESTS=$(${PYTHON} -c "import math; print(math.ceil(${QPS} * ${ACTUAL_DURATION} * 1.2))")
            echo "  ⚠️  数据集行数 ${DATASET_DATA_ROWS} 不足，时长自适应: ${DURATION_SECS}s → ${ACTUAL_DURATION}s"
        fi
        echo "  ▶ 发送 ${NUM_REQUESTS} 条请求（${ACTUAL_DURATION}s）"

        START_TIME=$(date +%s)

        cd "${LLM_BENCHMARK_ROOT}"
        BENCH_ARGS=(
            "--exp-name"               "${EXP_NAME}"
            "--dataset-path"           "${DATASET_PATH}"
            "--url"                    "${SERVER_URL}"
            "--model"                  "${TARGET_MODEL}"
            "--request-rate"           "${QPS}"
            "--num-requests"           "${NUM_REQUESTS}"
            "--request-time-limit"     "${ACTUAL_DURATION}"
            "--output-dir"             "${LEVEL_DIR}"
            "--tokenizer"              "${TOKENIZER}"
            "--max-completion-tokens"  "${MAX_COMPLETION_TOKENS}"
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
    echo "  ── 单档快速预览 qps=${QPS_TAG} ──"
    ${PYTHON} ${ANALYZE} \
        --phase 2 \
        --dir "${LEVEL_DIR}" \
        --ttfs-p90-limit ${TTFS_P90_LIMIT} \
        --e2e-p90-limit ${E2E_P90_LIMIT} \
        2>&1 || echo "  ⚠️  单档分析失败，继续下一档"

    if [[ "${QPS}" != "${GRID_LEVELS[-1]}" ]]; then
        echo "  💤 冷却 ${COOLDOWN_SECS}s ..."
        sleep "${COOLDOWN_SECS}"
    fi
done

echo ""
echo "========================================================"
echo "Phase 3 上线验证网格汇总（全档位）"
echo "========================================================"
${PYTHON} ${ANALYZE} \
    --phase 3 \
    --dir "${OUTPUT_BASE}" \
    --ttfs-p90-limit ${TTFS_P90_LIMIT} \
    --e2e-p90-limit ${E2E_P90_LIMIT} \
    --checkpoint "${CHECKPOINT}" \
    2>&1 || echo "  ⚠️  汇总分析失败"

echo ""
echo "========================================================"
echo "Phase 3 完成！"
echo "  ideal_rps   = ${IDEAL_RPS} req/s"
echo "  输出目录    = ${OUTPUT_BASE}"
echo "  检查点      = ${CHECKPOINT}"
echo ""
echo "下一步：用 qps-sweep-comparison Skill 生成图表"
echo "========================================================"
