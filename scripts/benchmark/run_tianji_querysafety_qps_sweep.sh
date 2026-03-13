#!/bin/bash
# tianji-querysafety-4b-v2-3  QPS 拐点扫描
#
# QPS 范围: 7.00 → 4.00（30 档，均等步进 ~0.103）
# 每档时长: 45min（2700s）
# 数据集:   tianji-querysafety-4b-v2-3_peak30min.csv（44,099 条，峰值 2168 RPM）
# 服务:     https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23/v1/chat/completions
#
# 用法：
#   后台执行：nohup bash scripts/benchmark/run_tianji_querysafety_qps_sweep.sh > /dev/null 2>&1 &
#   前台调试：bash scripts/benchmark/run_tianji_querysafety_qps_sweep.sh
#   查看进度：tail -f logs/tianji_qps_<timestamp>.log
#             cat logs/tianji_qps_<timestamp>/progress.txt

set -euo pipefail

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
BENCH_ROOT="/mnt/ai-infra/users/wnd/workspace/execute/speculative-decoding-benchmark"
BENCHMARK_SCRIPT="${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh"
VENV_BIN="${PROJECT_DIR}/.venv/bin"

TARGET_MODEL="/mnt/ai-llm/tianji_query_safety/v2p3_ep1"
TOKENIZER="/mnt/ai-llm/tianji_query_safety/v2p3_ep1"
DATASET_PATH="${PROJECT_DIR}/datas/output_tianji_querysafety/tianji-querysafety-4b-v2-3_peak30min.csv"
SERVER_URL="https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23/v1/chat/completions"

# 安全拦截模型输出短 JSON（{"label":...,"instruction":...}），不需要长输出
MAX_COMPLETION_TOKENS=256
COOLDOWN_SECS=60

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/tianji_qps_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/tianji_qps_${TIMESTAMP}.log"

# ============================================================
# QPS 档位（7.00 → 4.00，30 档，linspace 均等）
# ============================================================
declare -a QPS_LEVELS=(
    "7.00 2700"
    "6.90 2700"
    "6.79 2700"
    "6.69 2700"
    "6.59 2700"
    "6.48 2700"
    "6.38 2700"
    "6.28 2700"
    "6.17 2700"
    "6.07 2700"
    "5.97 2700"
    "5.86 2700"
    "5.76 2700"
    "5.66 2700"
    "5.55 2700"
    "5.45 2700"
    "5.34 2700"
    "5.24 2700"
    "5.14 2700"
    "5.03 2700"
    "4.93 2700"
    "4.83 2700"
    "4.72 2700"
    "4.62 2700"
    "4.52 2700"
    "4.41 2700"
    "4.31 2700"
    "4.21 2700"
    "4.10 2700"
    "4.00 2700"
)
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
echo "tianji-querysafety-4b-v2-3  QPS 拐点扫描"
echo "========================================================"
echo "  服务 URL:         ${SERVER_URL}"
echo "  数据集:           $(basename ${DATASET_PATH})  (44,099 条，峰值 2168 RPM)"
  echo "  QPS 范围:         7.00 → 4.00（${TOTAL_LEVELS} 档，步进 ~0.103）"
echo "  每档时长:         45min（2700s）"
echo "  冷却间隔:         ${COOLDOWN_SECS}s"
echo "  max_completion:   ${MAX_COMPLETION_TOKENS} tokens（短 JSON 输出）"
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
echo "total_levels=${TOTAL_LEVELS}" >> "${PROGRESS_FILE}"
echo "qps_range=7.00_to_4.00" >> "${PROGRESS_FILE}"
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
echo "分析结果:"
echo "  analysis --host 0.0.0.0 --port 8050 --exp ${OUTPUT_DIR}"
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_h=${ELAPSED_H}" >> "${PROGRESS_FILE}"
