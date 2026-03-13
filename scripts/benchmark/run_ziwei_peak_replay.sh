#!/bin/bash
# ziwei 32b 峰值流量回放
#
# 按数据集 income_time 时间戳回放请求，模拟真实流量形态（突发+低谷）
# 用途：验证服务在放大后的峰值负载下能否稳定运行（成功率/延迟符合预期）
#
# 对照：qps-benchmark-sweep 脚本（均匀 QPS 压测，找承载上限）
#
# 数据集说明：
#   poisson_29_stitched.csv  ← 接近线上实测峰值（16 RPM→29 RPM），保守验证
#   poisson_100_stitched.csv ← 监控平台峰值目标（100 RPM），极限验证 ★推荐
#
# 用法：
#   直接执行：bash scripts/benchmark/run_ziwei_peak_replay.sh
#   前台+日志：bash scripts/benchmark/run_ziwei_peak_replay.sh 2>&1 | tee logs/replay_manual.log

set -euo pipefail

# ============================================================
# 配置（按需修改）
# ============================================================
PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
VENV_BIN="${PROJECT_DIR}/.venv/bin"

TOKENIZER="/mnt/ai-llm/xinghan-ziwei-32b-v1"

# 数据集：选择目标 RPM 对应的插值文件
# poisson_29：接近实测峰值；poisson_100：监控平台峰值（推荐）
DATASET_PATH="${PROJECT_DIR}/datas/output/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_100_stitched.csv"
TARGET_RPM="100"    # 与数据集文件名保持一致，用于 exp-name 和输出目录命名

# 服务 URL（平台手动部署后提供）
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1/v1/chat/completions"

MAX_COMPLETION_TOKENS=4096   # 对话模型用 4096；安全拦截等短输出模型用 256

MODEL_NAME="ziwei"
EXP_NAME="${MODEL_NAME}_peak_replay_${TARGET_RPM}rpm"

# ============================================================
# 输出路径
# ============================================================
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${PROJECT_DIR}/logs/${MODEL_NAME}_peak_replay_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/${MODEL_NAME}_replay_${TIMESTAMP}.log"

# ============================================================
# 前置检查
# ============================================================
export PATH="${VENV_BIN}:${PATH}"

if [[ ! -f "${DATASET_PATH}" ]]; then
    echo "❌ 数据集不存在: ${DATASET_PATH}"
    exit 1
fi

DATASET_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))
mkdir -p "${OUTPUT_DIR}"

# ============================================================
# 启动摘要
# ============================================================
echo "========================================================"
echo "${MODEL_NAME} 峰值流量回放（keep-income-time 模式）"
echo "========================================================"
echo "  服务 URL:      ${SERVER_URL}"
echo "  数据集:        $(basename ${DATASET_PATH})"
echo "  数据集行数:    ${DATASET_ROWS} 条"
echo "  目标 RPM:      ${TARGET_RPM} RPM"
echo "  实验名称:      ${EXP_NAME}"
echo "  输出目录:      ${OUTPUT_DIR}"
echo "  日志文件:      ${LOG_FILE}"
echo ""
echo "  时长由数据 income_time 时间跨度决定（约 60 分钟）"
echo "  速率由 income_time 控制，非固定 QPS"
echo "========================================================"
echo ""

# ============================================================
# 执行回放
# ============================================================
"${VENV_BIN}/benchmark" \
    --exp-name "${EXP_NAME}" \
    --dataset-path "${DATASET_PATH}" \
    --url "${SERVER_URL}" \
    --tokenizer "${TOKENIZER}" \
    --keep-income-time \
    --no-kvcache \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
    --output-dir "${OUTPUT_DIR}" \
    2>&1 | tee "${LOG_FILE}"

# ============================================================
# 完成提示
# ============================================================
echo ""
echo "========================================================"
echo "回放完成"
echo "========================================================"
echo ""
echo "输出文件："
ls -lh "${OUTPUT_DIR}/"
echo ""
echo "分析结果："
echo "  analysis --host 0.0.0.0 --port 8050 --exp ${OUTPUT_DIR}"
echo "========================================================"
