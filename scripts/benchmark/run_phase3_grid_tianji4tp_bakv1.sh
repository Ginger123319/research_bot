#!/bin/bash
# Phase 3 上线验证网格 — tianji-querysafety-4b-v2-3 bakv1 4TP
#
# 在 [production_rps=7.47, ideal_rps] 区间均匀打 4 档稳态数据
# 每档 45min，供 qps-sweep-comparison 生成完整 SLA 曲线
#
# 必填环境变量：
#   IDEAL_RPS  Phase 2 输出的 ideal_rps
#
# 用法（手动）：
#   IDEAL_RPS=8.0 bash scripts/benchmark/run_phase3_grid_tianji4tp_bakv1.sh
# 用法（自动）：
#   由 run_all_phases_tianji4tp_bakv1.sh 自动调用

set -uo pipefail

IDEAL_RPS="${IDEAL_RPS:?必须设置 IDEAL_RPS（来自 Phase 2 输出）}"
# production_rps = 3584 RPM / 8实例 / 60 = 7.47 RPS/实例
PRODUCTION_RPS="7.47"

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23-bakv1/v1/chat/completions"
TARGET_MODEL="/mnt/ai-llm/tianji_query_safety/v2p3_ep1"
TOKENIZER="/mnt/ai-llm/tianji_query_safety/v2p3_ep1"
DATASET_PATH="${PROJECT_DIR}/datas/output_tianji_querysafety/tianji-querysafety-4b-v2-3_peak30min.csv"
MAX_COMPLETION_TOKENS=256

# ── 时间控制 ──────────────────────────────────────────────────
DURATION_SECS=2700    # 45min / 档
COOLDOWN_SECS=60

# ── SLA 阈值（同 Phase 2） ──────────────────────────────────
TTFS_P90_LIMIT=1.5    # 1500ms
E2E_P90_LIMIT=0.35    # 350ms (E2E P95 ≤ 400ms 保守代理)

# ── 处理 ideal_rps < production_rps 的边界情况 ───────────────
IDEAL_GTE_PROD=$(${PYTHON} -c "print('yes' if float('${IDEAL_RPS}') >= float('${PRODUCTION_RPS}') else 'no')")
if [[ "${IDEAL_GTE_PROD}" == "no" ]]; then
    echo "⚠️  ideal_rps (${IDEAL_RPS}) < production_rps (${PRODUCTION_RPS})，托底：使用 ideal_rps = production_rps"
    IDEAL_RPS="${PRODUCTION_RPS}"
fi

# ── 计算 4 档 linspace ────────────────────────────────────────
readarray -t GRID_LEVELS < <(${PYTHON} -c "
import numpy as np
pts = np.linspace(${PRODUCTION_RPS}, ${IDEAL_RPS}, 4)
for p in pts:
    print(f'{p:.4f}')
")

TIMESTAMP="$(date +%Y%m%d)"
OUTPUT_BASE="${PROJECT_DIR}/logs/tianji-querysafety-bakv1-phase3_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase3_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

DATASET_DATA_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))

echo "========================================================"
echo "Phase 3 上线验证网格 — tianji-querysafety bakv1 4TP"
echo "  production_rps = ${PRODUCTION_RPS}  ideal_rps = ${IDEAL_RPS}"
echo "  档位: ${GRID_LEVELS[*]}"
echo "  每档: ${DURATION_SECS}s = $((DURATION_SECS/60))min  冷却: ${COOLDOWN_SECS}s"
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
            echo "  ⚠️  数据集不足，时长自适应: ${DURATION_SECS}s → ${ACTUAL_DURATION}s"
        fi
        echo "  ▶ 发送 ${NUM_REQUESTS} 条请求（${ACTUAL_DURATION}s）"

        START_TIME=$(date +%s)

        cd "${LLM_BENCHMARK_ROOT}"
        BENCH_ARGS=(
            "--exp-name"              "${EXP_NAME}"
            "--dataset-path"          "${DATASET_PATH}"
            "--url"                   "${SERVER_URL}"
            "--model"                 "${TARGET_MODEL}"
            "--request-rate"          "${QPS}"
            "--num-requests"          "${NUM_REQUESTS}"
            "--request-time-limit"    "${ACTUAL_DURATION}"
            "--output-dir"            "${LEVEL_DIR}"
            "--tokenizer"             "${TOKENIZER}"
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
echo "  production_rps = ${PRODUCTION_RPS} req/s"
echo "  ideal_rps      = ${IDEAL_RPS} req/s"
echo "  输出目录       = ${OUTPUT_BASE}"
echo "  检查点         = ${CHECKPOINT}"
echo ""
echo "下一步：用 qps-sweep-comparison Skill 生成图表"
echo "========================================================"
