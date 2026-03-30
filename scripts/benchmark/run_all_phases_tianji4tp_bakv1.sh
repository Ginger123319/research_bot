#!/bin/bash
# 全流程编排 — tianji-querysafety-4b-v2-3 bakv1 4TP
#
# 自动串联执行 Phase 1 → Phase 2 → Phase 3，全程无需人工干预。
#
# 执行耗时估算：
#   Phase 1: ~40~60min（con=9 起跳，预计 3~4 档）
#   Phase 2: ~3~5h（每档 20min，预计 8~15 档逼近 ideal_rps≈8.0 RPS）
#   Phase 3: ~3h（4档 × 45min）
#   合计: ~7~9h
#
# 用法（后台执行，日志写入文件）：
#   nohup bash scripts/benchmark/run_all_phases_tianji4tp_bakv1.sh \
#     > logs/tianji_bakv1_all_phases_20260319.log 2>&1 &
#   echo "PID: $!"

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"

TIMESTAMP="$(date +%Y%m%d)"

echo "========================================================"
echo "全流程编排启动 — tianji-querysafety-4b-v2-3 bakv1 4TP"
echo "  Endpoint: https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23-bakv1/v1/chat/completions"
echo "  启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
echo ""

# ============================================================
# Phase 1：饱和探测
# ============================================================
echo "##########################################################"
echo "## Phase 1 开始 — $(date '+%Y-%m-%d %H:%M:%S')"
echo "##########################################################"

INIT_CON=9 bash "${PROJECT_DIR}/scripts/benchmark/run_phase1_auto_tianji4tp_bakv1.sh"

# 从 Phase 1 检查点提取 max_rps_estimate
P1_CHECKPOINT="${PROJECT_DIR}/logs/tianji-querysafety-bakv1-phase1_${TIMESTAMP}/phase1_checkpoint.md"
if [[ ! -f "${P1_CHECKPOINT}" ]]; then
    echo "❌ Phase 1 检查点未找到: ${P1_CHECKPOINT}"
    echo "   请检查 Phase 1 日志后手动设置 PEAK_RPS 和 START_RPS 重启 Phase 2"
    exit 1
fi

MAX_RPS=$(grep -oP 'max_rps_estimate\s*=\s*\K[\d.]+' "${P1_CHECKPOINT}" | tail -1)
if [[ -z "${MAX_RPS}" ]]; then
    echo "❌ 无法从检查点解析 max_rps_estimate"
    exit 1
fi
START_RPS=$(${PYTHON} -c "print(f'{float(\"${MAX_RPS}\") * 1.2:.4f}')")

echo ""
echo "✅ Phase 1 完成！"
echo "   max_rps_estimate = ${MAX_RPS} req/s"
echo "   Phase 2 起始 QPS = ${START_RPS} req/s"
echo ""

# ============================================================
# Phase 2：自适应逼近
# ============================================================
echo "##########################################################"
echo "## Phase 2 开始 — $(date '+%Y-%m-%d %H:%M:%S')"
echo "##########################################################"

PEAK_RPS="${MAX_RPS}" \
START_RPS="${START_RPS}" \
bash "${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_tianji4tp_bakv1.sh"

# 从 Phase 2 日志提取 ideal_rps
P2_LOG_DIR="${PROJECT_DIR}/logs/tianji-querysafety-bakv1-phase2_${TIMESTAMP}"
P2_CHECKPOINT="${P2_LOG_DIR}/phase2_checkpoint.md"

# 尝试从检查点文件提取
if [[ -f "${P2_CHECKPOINT}" ]]; then
    IDEAL_RPS=$(grep -oP 'ideal_rps\s*=\s*\K[\d.]+' "${P2_CHECKPOINT}" | tail -1)
fi

# 备用：从当前脚本输出的 stdout 提取（通过 tee 方式）
if [[ -z "${IDEAL_RPS:-}" ]]; then
    # 从 Phase 2 输出目录找最高通过的 rps
    IDEAL_RPS=$(ls -d "${P2_LOG_DIR}"/rps* 2>/dev/null | \
        xargs -I{} basename {} | sed 's/rps//' | \
        sort -n | tail -1 || true)
fi

if [[ -z "${IDEAL_RPS:-}" ]]; then
    echo "❌ 无法从 Phase 2 结果提取 ideal_rps"
    echo "   请手动设置 IDEAL_RPS 并运行："
    echo "   IDEAL_RPS=<值> bash scripts/benchmark/run_phase3_grid_tianji4tp_bakv1.sh"
    exit 1
fi

echo ""
echo "✅ Phase 2 完成！"
echo "   ideal_rps = ${IDEAL_RPS} req/s"
echo ""

# ============================================================
# Phase 3：上线验证网格
# ============================================================
echo "##########################################################"
echo "## Phase 3 开始 — $(date '+%Y-%m-%d %H:%M:%S')"
echo "##########################################################"

IDEAL_RPS="${IDEAL_RPS}" \
bash "${PROJECT_DIR}/scripts/benchmark/run_phase3_grid_tianji4tp_bakv1.sh"

# ============================================================
# 全流程完成
# ============================================================
echo ""
echo "##########################################################"
echo "## 全流程完成 — $(date '+%Y-%m-%d %H:%M:%S')"
echo "##########################################################"
echo ""
echo "产出目录："
echo "  Phase 1: ${PROJECT_DIR}/logs/tianji-querysafety-bakv1-phase1_${TIMESTAMP}/"
echo "  Phase 2: ${PROJECT_DIR}/logs/tianji-querysafety-bakv1-phase2_${TIMESTAMP}/"
echo "  Phase 3: ${PROJECT_DIR}/logs/tianji-querysafety-bakv1-phase3_${TIMESTAMP}/"
echo ""
echo "下一步："
echo "  1. 用 qps-sweep-comparison Skill 分析 Phase 3 结果，生成图表 + REPORT.md"
echo "  2. 对比 bakv1 与旧端点（4tp_fullrange_20260313）的曲线"
echo ""
echo "  ideal_rps       = ${IDEAL_RPS} req/s"
echo "  production_rps  = 7.47 req/s  (3584 RPM / 8实例 / 60)"
