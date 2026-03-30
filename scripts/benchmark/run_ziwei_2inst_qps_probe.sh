#!/bin/bash
# ziwei 32b 双实例部署 QPS 探测（短时快扫）
#
# 目标：验证 2 实例部署下 QPS 3.0~3.2 区间的服务承载能力
# QPS 范围：(3.0, 3.2) 开区间，均等 5 档
#   3.03 → 3.07 → 3.10 → 3.13 → 3.17
# 每档时长：15min（900s）
# 预计总时长：~1.4 小时（5×15min + 4×60s冷却）
#
# 用法：
#   后台执行：nohup bash scripts/benchmark/run_ziwei_2inst_qps_probe.sh > /dev/null 2>&1 &
#   前台调试：bash scripts/benchmark/run_ziwei_2inst_qps_probe.sh
#   查看进度：tail -f logs/ziwei_2inst_qps_<timestamp>.log
#             cat logs/ziwei_2inst_qps_<timestamp>/progress.txt

set -euo pipefail

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
BENCHMARK_SCRIPT="${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh"
VENV_BIN="${PROJECT_DIR}/.venv/bin"

TARGET_MODEL="/mnt/ai-llm/xinghan-ziwei-32b-v1"
TOKENIZER="/mnt/ai-llm/xinghan-ziwei-32b-v1"
DATASET_PATH="${PROJECT_DIR}/datas/output/xinghan-ziwei-32b-v1-1_all.csv"

# 服务 URL（2 实例部署，平台手动部署后提供）
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1/v1/chat/completions"

MAX_COMPLETION_TOKENS=4096
COOLDOWN_SECS=60

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/ziwei_2inst_qps_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/ziwei_2inst_qps_${TIMESTAMP}.log"

# ============================================================
# QPS 档位（开区间 (3.0, 3.2)，均等 5 档，step=0.033）
# 格式: "qps 时长(秒)"
# ============================================================
declare -a QPS_LEVELS=(
    "3.03 900"
    "3.07 900"
    "3.10 900"
    "3.13 900"
    "3.17 900"
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

DATASET_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))
echo "[INFO] 数据集行数（不含表头）: ${DATASET_ROWS}"

# ============================================================
# 启动摘要
# ============================================================
TOTAL_EST=$(( TOTAL_LEVELS * 900 + (TOTAL_LEVELS - 1) * COOLDOWN_SECS ))
TOTAL_EST_MIN=$(echo "scale=0; ${TOTAL_EST}/60" | bc)

echo "========================================================"
echo "ziwei 32b 双实例 QPS 快速探测"
echo "========================================================"
echo "  服务 URL:    ${SERVER_URL}"
echo "  部署配置:    2 实例（平台手动部署）"
echo "  数据集:      $(basename ${DATASET_PATH})  (${DATASET_ROWS} 条)"
echo "  QPS 范围:    (3.0, 3.2) 开区间，5 档均等"
echo "  每档时长:    15min（900s）"
echo "  冷却间隔:    ${COOLDOWN_SECS}s"
echo "  预计总时长:  ~${TOTAL_EST_MIN} 分钟"
echo "  输出目录:    ${OUTPUT_DIR}"
echo "  日志文件:    ${LOG_FILE}"
echo ""
printf "  %-8s %-12s %-12s\n" "QPS" "时长" "NUM_PROMPTS"
printf "  %-8s %-12s %-12s\n" "--------" "----------" "-----------"
for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    num=$(python3 -c "import math; print(math.ceil(${qps} * ${dur}))")
    printf "  %-8s %-12s %-12s\n" "${qps}" "15min" "${num}"
done
echo "========================================================"
echo ""

PROGRESS_FILE="${OUTPUT_DIR}/progress.txt"
echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')" > "${PROGRESS_FILE}"
echo "total_levels=${TOTAL_LEVELS}" >> "${PROGRESS_FILE}"
echo "qps_range=3.03_to_3.17" >> "${PROGRESS_FILE}"
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
    echo "档位 ${CURRENT}/${TOTAL_LEVELS}  QPS=${qps}  时长=15min  NUM_PROMPTS=${NUM_PROMPTS}"
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================================"

    {
        echo "current_level=${CURRENT}"
        echo "current_qps=${qps}"
        echo "current_start=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "elapsed_min=$(echo "scale=1; ($(date +%s) - ${START_TIME})/60" | bc)"
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
ELAPSED_MIN=$(echo "scale=1; ${ELAPSED}/60" | bc)

echo ""
echo "========================================================"
echo "全部 ${TOTAL_LEVELS} 档完成！实际耗时 ${ELAPSED_MIN} 分钟"
echo "========================================================"
echo ""
echo "分析结果："
echo "  analysis --host 0.0.0.0 --port 8050 --exp ${OUTPUT_DIR}"
echo ""
echo "各档位结果："
ls -1d "${OUTPUT_DIR}"/qps_* 2>/dev/null | while read d; do
    csv_count=$(ls "${d}"/*.csv 2>/dev/null | wc -l)
    printf "  %-12s  %d 个结果文件\n" "$(basename $d)" "${csv_count}"
done
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_min=${ELAPSED_MIN}" >> "${PROGRESS_FILE}"
