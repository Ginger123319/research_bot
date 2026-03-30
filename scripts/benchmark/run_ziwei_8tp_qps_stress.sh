#!/bin/bash
# 紫微 8TP 单实例 QPS 压力测试脚本（全量数据，拐点探测）
#
# 设计目标：
#   从高 QPS（1.0 req/s）向下扫描至 0.46，非均匀间隔，寻找性能拐点。
#   性能拐点预计在高 QPS 区，因此高处细粒度、低处粗扫：
#   - 边界区     ( 0.76~1.00 ) 0.02 步进细粒度，约 60 min / 档  ×13
#   - 中 QPS 段  ( 0.60~0.72 ) 0.04 步进，约 45 min / 档        × 4
#   - 低 QPS 段  ( 0.46~0.55 ) 0.05 步进粗扫，约 30 min / 档   × 3
#   共 20 档，总测试时长约 18 小时（含冷却间隔）
#
# 数据集：xinghan-ziwei-32b-v1-1_all.csv（12,789 条全量，read_only_time=False）
#
# 用法：
#   后台执行：nohup bash tmp/scripts/run_ziwei_8tp_qps_stress.sh > /dev/null 2>&1 &
#   前台调试：bash tmp/scripts/run_ziwei_8tp_qps_stress.sh
#
# 结果落在：logs/ziwei_8tp_qps_stress_<timestamp>/

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
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1/v1/chat/completions"

# 冷却时间（秒）：两档之间等待服务稳定
COOLDOWN_SECS=90

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/ziwei_8tp_qps_stress_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/ziwei_8tp_qps_stress_${TIMESTAMP}.log"

# ============================================================
# QPS 档位配置
# 格式: "qps 目标时长(秒)"
# NUM_PROMPTS 由 round(qps * 时长) 自动计算
# ============================================================
declare -a QPS_LEVELS=(
    # ── 边界区（高 QPS）：0.02 步进，约 60min / 档  共 13 档 ──
    "1.00 3600"
    "0.98 3600"
    "0.96 3600"
    "0.94 3600"
    "0.92 3600"
    "0.90 3600"
    "0.88 3600"
    "0.86 3600"
    "0.84 3600"
    "0.82 3600"
    "0.80 3600"
    "0.78 3600"
    "0.76 3600"
    # ── 中 QPS 段：0.04 步进，约 45min / 档  共 4 档 ──────────
    "0.72 2700"
    "0.68 2700"
    "0.64 2700"
    "0.60 2700"
    # ── 低 QPS 段：0.05 步进，约 30min / 档  共 3 档 ──────────
    "0.55 1800"
    "0.50 1800"
    "0.46 1800"
)
TOTAL_LEVELS=${#QPS_LEVELS[@]}

# ============================================================
# 初始化
# ============================================================
export PATH="${VENV_BIN}:${PATH}"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "$(dirname "${LOG_FILE}")"

# 所有输出同时写 LOG_FILE
exec > >(tee -a "${LOG_FILE}") 2>&1

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
echo "紫微 8TP 单实例 QPS 压力测试（拐点探测）"
echo "========================================================"
echo "  服务 URL:    ${SERVER_URL}"
echo "  数据集:      $(basename ${DATASET_PATH})"
echo "  QPS 档位:    ${TOTAL_LEVELS} 档（1.00 → 0.46，非均匀）"
echo "  冷却间隔:    ${COOLDOWN_SECS}s"
echo "  预计总时长:  ~${TOTAL_EST_H} 小时"
echo "  输出目录:    ${OUTPUT_DIR}"
echo "  日志文件:    ${LOG_FILE}"
echo ""
echo "  档位详情:"
printf "  %-8s %-10s %-12s\n" "QPS" "时长(min)" "NUM_PROMPTS"
printf "  %-8s %-10s %-12s\n" "--------" "----------" "-----------"
for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    num=$(python3 -c "import math; print(math.ceil(${qps} * ${dur}))")
    printf "  %-8s %-10s %-12s\n" "${qps}" "$((dur/60))min" "${num}"
done
echo "========================================================"
echo ""

# 进度状态文件（用于查看当前进度）
PROGRESS_FILE="${OUTPUT_DIR}/progress.txt"
echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')" > "${PROGRESS_FILE}"
echo "total_levels=${TOTAL_LEVELS}" >> "${PROGRESS_FILE}"

# ============================================================
# 主循环：逐档测试
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

    # 更新进度文件
    {
        echo "current_level=${CURRENT}"
        echo "current_qps=${qps}"
        echo "current_start=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "elapsed_h=$(echo "scale=1; ($(date +%s) - ${START_TIME})/3600" | bc)"
    } >> "${PROGRESS_FILE}"

    # 调用 benchmark（每档独立 OUTPUT_DIR 子目录）
    LEVEL_DIR="${OUTPUT_DIR}/TP8_qps_${qps}"
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
            echo "⚠️  档位 QPS=${qps} 执行异常（exit code $?），记录后继续下一档"
            echo "failed_qps_${CURRENT}=${qps}" >> "${PROGRESS_FILE}"
        }

    echo ""
    echo "✅ 档位 ${CURRENT}/${TOTAL_LEVELS} 完成  QPS=${qps}  结束时间: $(date '+%Y-%m-%d %H:%M:%S')"

    # 冷却（最后一档不等待）
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
echo "全部 ${TOTAL_LEVELS} 档测试完成！"
echo "  实际耗时: ${ELAPSED_H} 小时"
echo "  结果目录: ${OUTPUT_DIR}"
echo "========================================================"
echo ""
echo "结果子目录结构:"
ls -1d "${OUTPUT_DIR}"/TP8_qps_* 2>/dev/null | while read d; do
    csv_count=$(ls "${d}"/*.csv 2>/dev/null | wc -l)
    printf "  %-24s  %d 个结果文件\n" "$(basename $d)" "${csv_count}"
done
echo ""
echo "查看汇总分析："
echo "  cd ${BENCH_ROOT}/3rdparty/llm-benchmark"
echo "  analysis --exp ${OUTPUT_DIR}/TP8_qps_<level>"
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_h=${ELAPSED_H}" >> "${PROGRESS_FILE}"
