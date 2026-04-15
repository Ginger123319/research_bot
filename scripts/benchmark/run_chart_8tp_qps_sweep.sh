#!/bin/bash
# xinghan-chart-32b-v1-1-agent  QPS 拐点扫描（8TP部署）
#
# 场景:    推理模型长输出（max_completion_tokens=4096）
# QPS 范围: 2.0 → 4.0（20 档，均匀分布）
# 每档时长: 25min（1500s）  ← 数据集 6,016 条，QPS=4.0×1500=6,000 恰好满足
# 档位冷却: 90s
# 预计总时长: ~8.8 小时
# 数据集:   xinghan-chart-32b-v1-1-agent_all.csv（全量数据，QPS sweep 无需峰值采样）
# 服务:     https://infer.geniuworks.com/infra-xinghan-chart-p32b-v1-agent/v1/chat/completions
#
# ⚠️  启动前请先确认 endpoint 连通性：
#     curl https://infer.geniuworks.com/infra-xinghan-chart-p32b-v1-agent/health
#
# 用法：
#   后台执行：nohup bash scripts/benchmark/run_chart_8tp_qps_sweep.sh \
#               > logs/data-pipeline/chart_8tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &
#   查看进度：tail -f logs/data-pipeline/chart_8tp_qps_<timestamp>.log
#             cat logs/chart-32b-8tp/qps_<timestamp>/progress.txt

set -euo pipefail

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
BENCHMARK_SCRIPT="${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh"
VENV_BIN="${PROJECT_DIR}/.venv/bin"

TARGET_MODEL="/mnt/ai-llm/chartv5"
TOKENIZER="/mnt/ai-llm/chartv5"
DATASET_PATH="${PROJECT_DIR}/datas/output_chart/xinghan-chart-32b-v1-1-agent_all.csv"
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-chart-p32b-v1-agent/v1/chat/completions"

GROUP_NAME="chart-32b-8tp"
MAX_COMPLETION_TOKENS=4096   # 推理模型长输出场景
COOLDOWN_SECS=90

# QPS 扫描参数
QPS_START=2.0
QPS_END=4.0
NUM_LEVELS=20
DURATION=1500  # 25min/档（数据集 6,016 条，QPS=4.0×1500=6,000 恰好满足）

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/${GROUP_NAME}/qps_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/${GROUP_NAME}_qps_${TIMESTAMP}.log"

# ============================================================
# 生成 QPS 档位
# ============================================================
declare -a QPS_LEVELS=()
for i in $(seq 0 $((NUM_LEVELS - 1))); do
    qps=$(python3 -c "print(f'{${QPS_START} + (${QPS_END} - ${QPS_START}) * ${i} / (${NUM_LEVELS} - 1):.3f}')")
    QPS_LEVELS+=("${qps} ${DURATION}")
done
TOTAL_LEVELS=${#QPS_LEVELS[@]}

# ============================================================
# 初始化
# ============================================================
export PATH="${VENV_BIN}:${PATH}"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "$(dirname "${LOG_FILE}")"

exec > >(tee -a "${LOG_FILE}") 2>&1

# ============================================================
# 前置检查
# ============================================================
if [[ ! -f "${DATASET_PATH}" ]]; then
    echo "❌ 数据集不存在: ${DATASET_PATH}"
    exit 1
fi

if [[ ! -f "${BENCHMARK_SCRIPT}" ]]; then
    echo "❌ benchmark 脚本不存在: ${BENCHMARK_SCRIPT}"
    exit 1
fi

DATASET_ROWS=$(wc -l < "${DATASET_PATH}")
echo "[INFO] 数据集行数（含表头）: ${DATASET_ROWS}"

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
echo "xinghan-chart-32b-v1-1-agent  QPS 拐点扫描（8TP）"
echo "========================================================"
echo "  部署组:           ${GROUP_NAME}"
echo "  服务 URL:         ${SERVER_URL}"
echo "  数据集:           $(basename ${DATASET_PATH})  (峰值 120 RPM)"
echo "  QPS 范围:         ${QPS_START} → ${QPS_END}（${NUM_LEVELS} 档）"
    echo "  每档时长:         25min（1500s）"
echo "  冷却间隔:         ${COOLDOWN_SECS}s"
echo "  max_completion:   ${MAX_COMPLETION_TOKENS} tokens（推理模型长输出）"
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

PROGRESS_FILE="${OUTPUT_DIR}/progress.txt"
echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')" > "${PROGRESS_FILE}"
echo "group_name=${GROUP_NAME}" >> "${PROGRESS_FILE}"
echo "total_levels=${TOTAL_LEVELS}" >> "${PROGRESS_FILE}"
echo "qps_range=${QPS_START}_to_${QPS_END}" >> "${PROGRESS_FILE}"
echo "dataset=$(basename ${DATASET_PATH})" >> "${PROGRESS_FILE}"

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
    echo "档位 ${CURRENT}/${TOTAL_LEVELS}  QPS=${qps}  时长=45min  NUM_PROMPTS=${NUM_PROMPTS}"
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
    TARGET_MODEL="${TARGET_MODEL}" \
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
echo "分析结果（离线）:"
echo "  .venv/bin/python scripts/analysis/offline_analysis.py \\"
echo "    --csv logs/${GROUP_NAME}/qps_<timestamp>/qps_<N>/<exp>.csv \\"
echo "    --out results/chart_benchmark_<date>/<exp>_analysis.html \\"
echo "    --png-dir results/chart_benchmark_<date> \\"
echo "    --model-name xinghan-chart-32b-v1-1-agent"
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_h=${ELAPSED_H}" >> "${PROGRESS_FILE}"
