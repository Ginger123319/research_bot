#!/bin/bash
# 紫微 4TP 部署 QPS 压测脚本（补全缺失档位）
#
# 4TP 已完成档位（历史结果，不重复跑）：
#   logs/ziwei_4tp_qps_20260310_150343 → 0.84, 0.83, 0.82, 0.80, 0.50
#   logs/ziwei_4tp_qps_20260310_182639 → 0.49, 0.48
#   (0.47 进行中)
#
# 本脚本补全缺失的 16 档（对齐 8TP 压测覆盖范围 1.0 → 0.46）：
#   边界区 (0.02步, 60min): 1.00 → 0.86  共 8 档
#   中间区 (0.04步, 45min): 0.78 → 0.60  共 6 档
#   低 QPS (0.05步, 30min): 0.55, 0.46   共 2 档
#   合计 16 档，预估 ~14 小时
#
# 用法：
#   后台执行：nohup bash tmp/scripts/run_ziwei_4tp_qps_benchmark.sh > /dev/null 2>&1 &
#   前台调试：bash tmp/scripts/run_ziwei_4tp_qps_benchmark.sh

set -euo pipefail

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
BENCH_ROOT="/mnt/ai-infra/users/wnd/workspace/execute/speculative-decoding-benchmark"
BENCHMARK_SCRIPT="${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh"
VENV_BIN="/mnt/ai-infra/users/wnd/workspace/repo/SpecForge/.venv/bin"

TARGET_MODEL="/mnt/ai-llm/xinghan-ziwei-32b-v1"
TOKENIZER="/mnt/ai-llm/xinghan-ziwei-32b-v1"
DATASET_PATH="${PROJECT_DIR}/datas/output/xinghan-ziwei-32b-v1-1_all.csv"
SERVER_URL="https://infer.geniuworks.com/infra-opti-xinghan-ziwei-p32b-v1/v1/chat/completions"

COOLDOWN_SECS=90

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/ziwei_4tp_qps_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/ziwei_4tp_qps_${TIMESTAMP}.log"

# ============================================================
# 待补全档位（跳过已完成的 0.84/0.83/0.82/0.80/0.50/0.49/0.48/0.47）
# 格式: "qps 目标时长(秒)"
# ============================================================
declare -a QPS_LEVELS=(
    # ── 边界区 (0.02 步进, 60min / 档)  共 8 档 ──────────────
    "1.00 3600"
    "0.98 3600"
    "0.96 3600"
    "0.94 3600"
    "0.92 3600"
    "0.90 3600"
    "0.88 3600"
    "0.86 3600"
    # ── 中间区 (0.04 步进, 45min / 档)  共 6 档 ──────────────
    "0.78 2700"
    "0.76 2700"
    "0.72 2700"
    "0.68 2700"
    "0.64 2700"
    "0.60 2700"
    # ── 低 QPS (0.05 步进, 30min / 档)  共 2 档 ──────────────
    "0.55 1800"
    "0.46 1800"
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
echo "紫微 4TP QPS 压测（补全缺失档位，对齐 8TP 覆盖范围）"
echo "========================================================"
echo "  服务 URL:    ${SERVER_URL}"
echo "  数据集:      $(basename ${DATASET_PATH})  (12,789 条全量)"
echo "  补全档位:    ${TOTAL_LEVELS} 档（缺口补全，跳过已完成）"
echo "  冷却间隔:    ${COOLDOWN_SECS}s"
echo "  预计总时长:  ~${TOTAL_EST_H} 小时"
echo "  输出目录:    ${OUTPUT_DIR}"
echo "  日志文件:    ${LOG_FILE}"
echo ""
echo "  已完成历史档位："
echo "    20260310_150343 → 0.84, 0.83, 0.82, 0.80, 0.50"
echo "    20260310_182639 → 0.49, 0.48, 0.47"
echo ""
echo "  本次补全档位详情："
printf "  %-8s %-10s %-12s %-10s\n" "QPS" "时长(min)" "NUM_PROMPTS" "区段"
printf "  %-8s %-10s %-12s %-10s\n" "--------" "----------" "-----------" "--------"
for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    num=$(python3 -c "import math; print(math.ceil(${qps} * ${dur}))")
    qps_f=$(echo "${qps}" | awk '{printf "%.2f", $1}')
    zone="边界(0.02步)" 
    [[ $(echo "${qps} < 0.79" | bc -l) -eq 1 ]] && zone="中间(0.04步)"
    [[ $(echo "${qps} < 0.59" | bc -l) -eq 1 ]] && zone="低QPS(0.05步)"
    printf "  %-8s %-10s %-12s %-10s\n" "${qps_f}" "$((dur/60))min" "${num}" "${zone}"
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
echo "全部 ${TOTAL_LEVELS} 档补全完成！实际耗时 ${ELAPSED_H} 小时"
echo "========================================================"
echo ""
echo "合并全部 4TP 结果（含历史）进行完整分析："
echo "  历史 → ${PROJECT_DIR}/logs/ziwei_4tp_qps_20260310_150343"
echo "  历史 → ${PROJECT_DIR}/logs/ziwei_4tp_qps_20260310_182639"
echo "  本次 → ${OUTPUT_DIR}"
echo ""
echo "结果子目录："
ls -1d "${OUTPUT_DIR}"/TP4_qps_* 2>/dev/null | while read d; do
    csv_count=$(ls "${d}"/*.csv 2>/dev/null | wc -l)
    printf "  %-24s  %d 个结果文件\n" "$(basename $d)" "${csv_count}"
done
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_h=${ELAPSED_H}" >> "${PROGRESS_FILE}"
