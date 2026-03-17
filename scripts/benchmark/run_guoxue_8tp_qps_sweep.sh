#!/bin/bash
# xinghan-guoxue-72b-v1-2-reason  QPS 拐点扫描
#
# 场景:    长推理对话（input ~4K, output ~4K tokens）
# QPS 范围: 0.190 → 0.350（24 档，两头精细 + 中间粗粒度）
#   低端精细（0.005步进, 7档）: 0.190 ~ 0.220
#   中间区（0.010步进, 10档）:  0.225 ~ 0.315
#   高端精细（0.005步进, 7档）: 0.320 ~ 0.350
# 每档时长: 60min（3600s）
# 档位冷却: 90s
# 预计总时长: ~24.5 小时
# 数据集:   xinghan-guoxue-72b-v1-2-reason_all.csv（23,361 条）
# 服务:     https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions
#
# ⚠️  启动前请先确认 endpoint 连通性：
#     curl https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/health
#
# 用法：
#   后台执行：nohup bash scripts/benchmark/run_guoxue_8tp_qps_sweep.sh \
#               > logs/data-pipeline/guoxue_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &
#   查看进度：tail -f logs/data-pipeline/guoxue_qps_<timestamp>.log
#             cat logs/guoxue_8tp_qps_<timestamp>/progress.txt

set -euo pipefail

# ============================================================
# 路径配置
# ============================================================
PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
BENCH_ROOT="/mnt/ai-infra/users/wnd/workspace/execute/speculative-decoding-benchmark"
BENCHMARK_SCRIPT="${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh"
VENV_BIN="${PROJECT_DIR}/.venv/bin"

TARGET_MODEL="/mnt/ai-llm/l83v2-G1-400"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_full.csv"
SERVER_URL="https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions"

MAX_COMPLETION_TOKENS=4096   # 长推理输出场景，与业务真实 token 对齐
COOLDOWN_SECS=90

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/guoxue_8tp_qps_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/guoxue_8tp_qps_${TIMESTAMP}.log"

# ============================================================
# QPS 档位（24档，60min/档）
# 低端精细（0.005步进）+ 中间（0.010步进）+ 高端精细（0.005步进）
# ============================================================
declare -a QPS_LEVELS=(
    # 低端精细区（近线上 0.195，步进 0.005，7档）
    "0.190 3600"
    "0.195 3600"
    "0.200 3600"
    "0.205 3600"
    "0.210 3600"
    "0.215 3600"
    "0.220 3600"
    # 中间区（步进 0.010，10档）
    "0.225 3600"
    "0.235 3600"
    "0.245 3600"
    "0.255 3600"
    "0.265 3600"
    "0.275 3600"
    "0.285 3600"
    "0.295 3600"
    "0.305 3600"
    "0.315 3600"
    # 高端精细区（近已知上限 0.34，步进 0.005，7档）
    "0.320 3600"
    "0.325 3600"
    "0.330 3600"
    "0.335 3600"
    "0.340 3600"
    "0.345 3600"
    "0.350 3600"
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
echo "xinghan-guoxue-72b-v1-2-reason  QPS 拐点扫描（8TP）"
echo "========================================================"
echo "  服务 URL:         ${SERVER_URL}"
echo "  数据集:           $(basename ${DATASET_PATH})  (23,357 条，两日合并)"
echo "  QPS 范围:         0.190 → 0.350（${TOTAL_LEVELS} 档，两头精细+中间粗粒度）"
echo "  每档时长:         60min（3600s）"
echo "  冷却间隔:         ${COOLDOWN_SECS}s"
echo "  max_completion:   ${MAX_COMPLETION_TOKENS} tokens（长推理场景）"
echo "  预计总时长:       ~${TOTAL_EST_H} 小时"
echo "  输出目录:         ${OUTPUT_DIR}"
echo "  日志文件:         ${LOG_FILE}"
echo ""
printf "  %-8s %-12s %-10s %-10s\n" "QPS" "NUM_PROMPTS" "时长" "区域"
printf "  %-8s %-12s %-10s %-10s\n" "--------" "-----------" "------" "------"
for entry in "${QPS_LEVELS[@]}"; do
    read -r qps dur <<< "$entry"
    num=$(python3 -c "import math; print(math.ceil(${qps} * ${dur}))")
    # 标注区域
    qps_val=$(python3 -c "print(${qps})")
    if python3 -c "exit(0 if ${qps} <= 0.220 else 1)"; then
        zone="低端精细"
    elif python3 -c "exit(0 if ${qps} <= 0.315 else 1)"; then
        zone="中间区"
    else
        zone="高端精细"
    fi
    printf "  %-8s %-12s %-10s %-10s\n" "${qps}" "${num}" "$((dur/60))min" "${zone}"
done
echo "========================================================"
echo ""

PROGRESS_FILE="${OUTPUT_DIR}/progress.txt"
echo "started_at=$(date '+%Y-%m-%d %H:%M:%S')" > "${PROGRESS_FILE}"
echo "total_levels=${TOTAL_LEVELS}" >> "${PROGRESS_FILE}"
echo "qps_range=0.190_to_0.350" >> "${PROGRESS_FILE}"
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
    echo "档位 ${CURRENT}/${TOTAL_LEVELS}  QPS=${qps}  时长=60min  NUM_PROMPTS=${NUM_PROMPTS}"
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
echo "    --csv logs/guoxue_8tp_qps_<timestamp>/qps_<N>/<exp>.csv \\"
echo "    --out results/guoxue_benchmark_<date>/<exp>_analysis.html \\"
echo "    --png-dir results/guoxue_benchmark_<date> \\"
echo "    --model-name xinghan-guoxue-72b-v1-2-reason"
echo "========================================================"

echo "completed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "${PROGRESS_FILE}"
echo "actual_elapsed_h=${ELAPSED_H}" >> "${PROGRESS_FILE}"
