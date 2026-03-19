#!/bin/bash
# 通用 QPS 拐点扫描脚本
#
# 用法：
#   nohup bash scripts/benchmark/run_qps_sweep.sh <config.env> \
#       > logs/data-pipeline/<model>_<tp>_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &
#
# 配置文件：configs/models/<model>/<tp>.env
# 设计文档：clingo/docs/designs/2026-03-18-generic-benchmark-runner-design.md

set -euo pipefail

# ============================================================
# 载入配置
# ============================================================
CONFIG_ENV="${1:-}"
if [[ -z "${CONFIG_ENV}" ]]; then
    echo "❌ 用法: bash $0 <config.env>"
    echo "   示例: bash $0 configs/models/xinghan-chart-32b-v1-1-agent/8tp.env"
    exit 1
fi
if [[ ! -f "${CONFIG_ENV}" ]]; then
    echo "❌ 配置文件不存在: ${CONFIG_ENV}"
    exit 1
fi
source "${CONFIG_ENV}"

# ============================================================
# 固定路径（不随模型变化）
# ============================================================
PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
BENCH_ROOT="/mnt/ai-infra/users/wnd/workspace/execute/speculative-decoding-benchmark"
BENCHMARK_SCRIPT="${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh"
VENV_BIN="${PROJECT_DIR}/.venv/bin"

# 补全相对路径
[[ "${DATASET_PATH}" != /* ]] && DATASET_PATH="${PROJECT_DIR}/${DATASET_PATH}"

# ============================================================
# 参数校验
# ============================================================
REQUIRED_VARS=(MODEL_NAME MODEL_PATH TOKENIZER DATASET_PATH SERVER_URL
               GROUP_NAME MAX_COMPLETION_TOKENS COOLDOWN_SECS
               QPS_START QPS_END NUM_LEVELS DURATION)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ 配置缺失: ${var}（检查 ${CONFIG_ENV}）"
        exit 1
    fi
done

if [[ ! -f "${DATASET_PATH}" ]]; then
    echo "❌ 数据集不存在: ${DATASET_PATH}"
    exit 1
fi
if [[ ! -f "${BENCHMARK_SCRIPT}" ]]; then
    echo "❌ benchmark 脚本不存在: ${BENCHMARK_SCRIPT}"
    exit 1
fi

# ============================================================
# 初始化
# ============================================================
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/${GROUP_NAME}/qps_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/data-pipeline/${GROUP_NAME}_qps_${TIMESTAMP}.log"

export PATH="${VENV_BIN}:${PATH}"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "$(dirname "${LOG_FILE}")"

exec > >(tee -a "${LOG_FILE}") 2>&1

# ============================================================
# 生成 QPS 档位
# ============================================================
declare -a QPS_LEVELS=()
for i in $(seq 0 $((NUM_LEVELS - 1))); do
    qps=$(python3 -c "print(f'{${QPS_START} + (${QPS_END} - ${QPS_START}) * ${i} / (${NUM_LEVELS} - 1):.3f}')")
    QPS_LEVELS+=("${qps} ${DURATION}")
done
TOTAL_LEVELS=${#QPS_LEVELS[@]}

DATASET_ROWS=$(wc -l < "${DATASET_PATH}")

# ============================================================
# 启动摘要
# ============================================================
TOTAL_EST=0
for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    TOTAL_EST=$((TOTAL_EST + dur + COOLDOWN_SECS))
done
TOTAL_EST_H=$(echo "scale=1; ${TOTAL_EST}/3600" | bc)

echo "========================================================"
echo "${MODEL_NAME}  QPS 拐点扫描"
echo "========================================================"
echo "  配置文件:         ${CONFIG_ENV}"
echo "  部署组:           ${GROUP_NAME}"
echo "  服务 URL:         ${SERVER_URL}"
echo "  数据集:           $(basename ${DATASET_PATH})  (${DATASET_ROWS} 行含表头)"
echo "  QPS 范围:         ${QPS_START} → ${QPS_END}（${NUM_LEVELS} 档）"
echo "  每档时长:         $((DURATION/60))min（${DURATION}s）"
echo "  冷却间隔:         ${COOLDOWN_SECS}s"
echo "  max_completion:   ${MAX_COMPLETION_TOKENS} tokens"
echo "  预计总时长:       ~${TOTAL_EST_H} 小时"
echo "  输出目录:         ${OUTPUT_DIR}"
echo "  日志文件:         ${LOG_FILE}"
echo ""
printf "  %-8s %-12s %-10s\n" "QPS" "NUM_PROMPTS" "时长"
printf "  %-8s %-12s %-10s\n" "--------" "-----------" "------"
for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    num=$(python3 -c "import math; print(math.ceil(${qps} * ${dur}))")
    printf "  %-8s %-12s %-10s\n" "${qps}" "${num}" "$((dur/60))min"
done
echo "========================================================"
echo ""

# ============================================================
# 进度文件
# ============================================================
PROGRESS_FILE="${OUTPUT_DIR}/progress.txt"
echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')" > "${PROGRESS_FILE}"
echo "config=${CONFIG_ENV}" >> "${PROGRESS_FILE}"
echo "group_name=${GROUP_NAME}" >> "${PROGRESS_FILE}"
echo "total_levels=${TOTAL_LEVELS}" >> "${PROGRESS_FILE}"
echo "qps_range=${QPS_START}_to_${QPS_END}" >> "${PROGRESS_FILE}"
echo "dataset=$(basename ${DATASET_PATH})" >> "${PROGRESS_FILE}"

# ============================================================
# 写实验目录 README（规范：每个实验目录必须有 README）
# ============================================================
cat > "${OUTPUT_DIR}/README.md" << EOF
# ${GROUP_NAME} QPS 拐点扫描

## 实验信息

| 项目 | 内容 |
|------|------|
| 模型 | ${MODEL_NAME} |
| 配置文件 | ${CONFIG_ENV} |
| 服务 URL | ${SERVER_URL} |
| 数据集 | $(basename ${DATASET_PATH}) |
| 执行时间 | $(date '+%Y-%m-%d %H:%M:%S') |

## 配置参数

- QPS 范围：${QPS_START} → ${QPS_END}（${NUM_LEVELS} 档，每档 $((DURATION/60))min）
- 冷却间隔：${COOLDOWN_SECS}s
- max_completion_tokens：${MAX_COMPLETION_TOKENS}
- 预计总时长：~${TOTAL_EST_H} 小时

## 结果指针

- 分析报告 → \`results/<report_dir>/REPORT.md\`（sweep 完成后更新）
- 模型汇总 → \`results/models/${MODEL_NAME}/model-context.md\`
EOF

# ============================================================
# 主循环
# ============================================================
cd "${BENCH_ROOT}"
CURRENT=0
START_TIME=$(date +%s)

for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    CURRENT=$((CURRENT + 1))
    NUM_PROMPTS=$(python3 -c "import math; print(math.ceil(${qps} * ${dur}))")

    echo ""
    echo "========================================================"
    echo "档位 ${CURRENT}/${TOTAL_LEVELS}  QPS=${qps}  时长=$((dur/60))min  NUM_PROMPTS=${NUM_PROMPTS}"
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================================"

    {
        echo "current_level=${CURRENT}"
        echo "current_qps=${qps}"
        echo "current_start=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "elapsed_h=$(echo "scale=1; ($(date +%s) - ${START_TIME})/3600" | bc)"
    } >> "${PROGRESS_FILE}"

    LEVEL_DIR="${OUTPUT_DIR}/qps_${qps}"
    mkdir -p "${LEVEL_DIR}"

    NUM_PROMPTS="${NUM_PROMPTS}" \
    TARGET_MODEL="${MODEL_PATH}" \
    TOKENIZER="${TOKENIZER}" \
    CONFIG_LIST="${qps},0,0,0" \
    DATASET_PATH="${DATASET_PATH}" \
    OUTPUT_DIR="${LEVEL_DIR}" \
    bash "${BENCHMARK_SCRIPT}" \
        --skip-launch-server \
        --server-url "${SERVER_URL}" \
        --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
        || {
            echo ""
            echo "⚠️  档位 QPS=${qps} 执行异常（exit code $?），记录后继续"
            echo "failed_qps_${CURRENT}=${qps}" >> "${PROGRESS_FILE}"
        }

    echo ""
    echo "✅ 档位 ${CURRENT}/${TOTAL_LEVELS} 完成  QPS=${qps}  结束: $(date '+%Y-%m-%d %H:%M:%S')"

    if [[ ${CURRENT} -lt ${TOTAL_LEVELS} ]]; then
        echo "   等待 ${COOLDOWN_SECS}s 冷却..."
        sleep "${COOLDOWN_SECS}"
    fi
done

# ============================================================
# 完成汇总
# ============================================================
ELAPSED=$(( $(date +%s) - START_TIME ))
ELAPSED_H=$(echo "scale=1; ${ELAPSED}/3600" | bc)

echo ""
echo "========================================================"
echo "全部 ${TOTAL_LEVELS} 档完成！实际耗时 ${ELAPSED_H} 小时"
echo "========================================================"
echo ""
echo "结果目录:"
ls -1d "${OUTPUT_DIR}"/qps_* 2>/dev/null | while read d; do
    csv_count=$(ls "${d}"/*.csv 2>/dev/null | wc -l)
    printf "  %-20s  %d 个结果文件\n" "$(basename $d)" "${csv_count}"
done
echo ""
echo "下一步（qps-sweep-comparison Skill）:"
echo "  .venv/bin/python scripts/analysis/offline_analysis.py \\"
echo "    --exp-dir ${OUTPUT_DIR} \\"
echo "    --model-name ${MODEL_NAME}"
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_h=${ELAPSED_H}" >> "${PROGRESS_FILE}"
