#!/bin/bash
# 紫微 4TP 部署 高QPS 均等探索脚本（含 QPS=1.0 重跑）
#
# 背景：
#   2026-03-10 4TP 跑 QPS=1.0 的结果存在异常，需要重跑。
#   同时对齐 8TP 高QPS探索范围，在 [1.0, 2.0] 均等扫描以定位边界区。
#
# 设计目标：
#   QPS [1.0, 2.0] 均等分 11 档，步进 0.1，每档发送约 30 min。
#   发送完成后等待响应回收，总时长控制在 1 小时内。
#   QPS=1.0 为重跑档（上次结果异常）。
#   共 11 档，总测试时长约 6 小时（含冷却间隔）
#
# 数据集：xinghan-ziwei-32b-v1-1_all.csv（12,789 条全量，read_only_time=False）
#
# 用法：
#   后台执行：nohup bash tmp/scripts/run_ziwei_4tp_high_qps_explore.sh > /dev/null 2>&1 &
#   前台调试：bash tmp/scripts/run_ziwei_4tp_high_qps_explore.sh
#
# 结果落在：logs/ziwei_4tp_high_qps_<timestamp>/

set -euo pipefail

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
BENCHMARK_SCRIPT="${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh"
VENV_BIN="/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/bin"

TARGET_MODEL="/mnt/ai-llm/xinghan-ziwei-32b-v1"
TOKENIZER="/mnt/ai-llm/xinghan-ziwei-32b-v1"
DATASET_PATH="${PROJECT_DIR}/datas/output/xinghan-ziwei-32b-v1-1_all.csv"
SERVER_URL="https://infer.geniuworks.com/infra-opti-xinghan-ziwei-p32b-v1/v1/chat/completions"

# 冷却时间（秒）：两档之间等待服务稳定
COOLDOWN_SECS=90

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/ziwei_4tp_high_qps_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/ziwei_4tp_high_qps_${TIMESTAMP}.log"

# ============================================================
# QPS 档位配置（高QPS均等探索 + QPS=1.0 重跑）
# 格式: "qps 目标时长(秒)"
# NUM_PROMPTS 由 ceil(qps * 时长) 自动计算
# ============================================================
declare -a QPS_LEVELS=(
    # ── 高 QPS 均等探索区 [1.0, 2.0]：0.10 步进，发送约 30min / 档  共 11 档 ──
    "2.00 2700"
    "1.90 2700"
    "1.80 2700"
    "1.70 2700"
    "1.60 2700"
    "1.50 2700"
    "1.40 2700"
    "1.30 2700"
    "1.20 2700"
    "1.10 2700"
    "1.00 2700"   # 重跑（上次结果异常）
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
# 数据集检查
# ============================================================
if [[ ! -f "${DATASET_PATH}" ]]; then
    echo "❌ 数据集不存在: ${DATASET_PATH}"
    exit 1
fi

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
echo "紫微 4TP 高QPS 边界探索（2.0 → 1.0，均等 11 档，含1.0重跑）"
echo "========================================================"
echo "  服务 URL:    ${SERVER_URL}"
echo "  数据集:      $(basename ${DATASET_PATH})  (12,789 条全量)"
echo "  QPS 档位:    ${TOTAL_LEVELS} 档（2.00 → 1.00，步进 0.10，发送 30min/档）"
echo "  冷却间隔:    ${COOLDOWN_SECS}s"
echo "  预计总时长:  ~${TOTAL_EST_H} 小时"
echo "  输出目录:    ${OUTPUT_DIR}"
echo "  日志文件:    ${LOG_FILE}"
echo ""
echo "  档位详情："
printf "  %-8s %-10s %-12s %-14s\n" "QPS" "时长(min)" "NUM_PROMPTS" "备注"
printf "  %-8s %-10s %-12s %-14s\n" "--------" "----------" "-----------" "--------"
for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    num=$(python3 -c "import math; print(math.ceil(${qps} * ${dur}))")
    qps_f=$(echo "${qps}" | awk '{printf "%.2f", $1}')
    note=""
    [[ "${qps}" == "1.00" ]] && note="重跑(上次异常)"
    printf "  %-8s %-10s %-12s %-14s\n" "${qps_f}" "$((dur/60))min" "${num}" "${note}"
done
echo "========================================================"
echo ""

PROGRESS_FILE="${OUTPUT_DIR}/progress.txt"
echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')" > "${PROGRESS_FILE}"
echo "total_levels=${TOTAL_LEVELS}" >> "${PROGRESS_FILE}"

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
    echo "档位 ${CURRENT}/${TOTAL_LEVELS}  QPS=${qps}  时长≈$((dur/60))min  NUM_PROMPTS=${NUM_PROMPTS}"
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "========================================================"

    {
        echo "current_level=${CURRENT}"
        echo "current_qps=${qps}"
        echo "current_start=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "elapsed_h=$(echo "scale=1; ($(date +%s) - ${START_TIME})/3600" | bc)"
    } >> "${PROGRESS_FILE}"

    LEVEL_DIR="${OUTPUT_DIR}/TP4_qps_${qps}"
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
        --max-completion-tokens 4096 \
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
echo "全部 ${TOTAL_LEVELS} 档高QPS探索完成！实际耗时 ${ELAPSED_H} 小时"
echo "========================================================"
echo ""
echo "4TP 本次高QPS结果目录：${OUTPUT_DIR}"
echo ""
echo "结果子目录："
ls -1d "${OUTPUT_DIR}"/TP4_qps_* 2>/dev/null | while read d; do
    csv_count=$(ls "${d}"/*.csv 2>/dev/null | wc -l)
    printf "  %-24s  %d 个结果文件\n" "$(basename $d)" "${csv_count}"
done
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_h=${ELAPSED_H}" >> "${PROGRESS_FILE}"
