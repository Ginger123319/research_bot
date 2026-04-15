#!/bin/bash
# 通用峰值流量回放脚本
#
# 用法：
#   nohup bash scripts/benchmark/run_replay.sh configs/models/<model>/<tp>.env &
#
#   脚本自动管理日志：
#     pipeline 日志 → logs/data-pipeline/{GROUP_NAME}_replay_{TIMESTAMP}.log
#     实验结果目录  → logs/{MODEL_NAME}/{GROUP_NAME}_replay_{TIMESTAMP}/
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
# 固定路径
# ============================================================
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV_BIN="${PROJECT_DIR}/.venv/bin"

# 补全相对路径
[[ "${REPLAY_DATASET_PATH}" != /* ]] && REPLAY_DATASET_PATH="${PROJECT_DIR}/${REPLAY_DATASET_PATH}"

# ============================================================
# 参数校验
# ============================================================
if [[ -z "${REPLAY_DATASET_PATH:-}" || -z "${REPLAY_RPM:-}" ]]; then
    echo "❌ 回放参数未配置：REPLAY_DATASET_PATH 或 REPLAY_RPM 为空"
    echo "   请在 ${CONFIG_ENV} 中填写 REPLAY_* 字段"
    exit 1
fi
if [[ ! -f "${REPLAY_DATASET_PATH}" ]]; then
    echo "❌ 回放数据集不存在: ${REPLAY_DATASET_PATH}"
    exit 1
fi

REQUIRED_VARS=(MODEL_NAME TOKENIZER SERVER_URL GROUP_NAME MAX_COMPLETION_TOKENS)
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "❌ 配置缺失: ${var}（检查 ${CONFIG_ENV}）"
        exit 1
    fi
done

# ============================================================
# 初始化
# ============================================================
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
EXP_NAME="${GROUP_NAME}_replay_${REPLAY_RPM}rpm"
MODEL_LOG_DIR="${PROJECT_DIR}/logs/${MODEL_NAME}"
OUTPUT_DIR="${MODEL_LOG_DIR}/${GROUP_NAME}_replay_${TIMESTAMP}"
LOG_FILE="${PROJECT_DIR}/logs/data-pipeline/${GROUP_NAME}_replay_${TIMESTAMP}.log"

export PATH="${VENV_BIN}:${PATH}"
mkdir -p "${MODEL_LOG_DIR}"
mkdir -p "${OUTPUT_DIR}"
mkdir -p "$(dirname "${LOG_FILE}")"

exec > >(tee -a "${LOG_FILE}") 2>&1

DATASET_ROWS=$(( $(wc -l < "${REPLAY_DATASET_PATH}") - 1 ))

# ============================================================
# 启动摘要
# ============================================================
echo "========================================================"
echo "${MODEL_NAME}  峰值流量回放（keep-income-time 模式）"
echo "========================================================"
echo "  配置文件:     ${CONFIG_ENV}"
echo "  部署组:       ${GROUP_NAME}"
echo "  服务 URL:     ${SERVER_URL}"
echo "  数据集:       $(basename ${REPLAY_DATASET_PATH})"
echo "  数据集行数:   ${DATASET_ROWS} 条"
echo "  目标 RPM:     ${REPLAY_RPM} RPM"
echo "  实验名称:     ${EXP_NAME}"
echo "  输出目录:     ${OUTPUT_DIR}"
echo "  日志文件:     ${LOG_FILE}"
echo ""
echo "  时长由 income_time 时间跨度决定"
echo "  速率由 income_time 控制（非固定 QPS）"
echo "========================================================"
echo ""

# ============================================================
# 写实验目录 README
# ============================================================
cat > "${OUTPUT_DIR}/README.md" << EOF
# ${GROUP_NAME} 峰值回放

## 实验信息

| 项目 | 内容 |
|------|------|
| 模型 | ${MODEL_NAME} |
| 配置文件 | ${CONFIG_ENV} |
| 服务 URL | ${SERVER_URL} |
| 数据集 | $(basename ${REPLAY_DATASET_PATH}) |
| 目标 RPM | ${REPLAY_RPM} RPM |
| 执行时间 | $(date '+%Y-%m-%d %H:%M:%S') |

## 说明

峰值回放按 \`income_time\` 时间戳重放请求，模拟真实流量形态（突发+低谷），
与 QPS sweep 均匀施压不同，用于验证真实流量形态下的 SLA。

## 结果指针

- 分析报告 → \`results/<report_dir>/REPORT.md\`（回放完成后更新）
- 模型汇总 → \`results/models/${MODEL_NAME}/model-context.md\`
EOF

# ============================================================
# 执行回放
# ============================================================
"${VENV_BIN}/benchmark" \
    --exp-name "${EXP_NAME}" \
    --dataset-path "${REPLAY_DATASET_PATH}" \
    --url "${SERVER_URL}" \
    --tokenizer "${TOKENIZER}" \
    --keep-income-time \
    --no-kvcache \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
    --output-dir "${OUTPUT_DIR}"

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
echo "下一步（benchmark-result-analysis Skill）："
echo "  .venv/bin/python scripts/analysis/offline_analysis.py \\"
echo "    --csv ${OUTPUT_DIR}/${EXP_NAME}.csv \\"
echo "    --out results/<report_dir>/${EXP_NAME}_analysis.html \\"
echo "    --model-name ${MODEL_NAME}"
echo "========================================================"
