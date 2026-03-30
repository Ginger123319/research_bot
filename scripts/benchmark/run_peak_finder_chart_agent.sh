#!/bin/bash
# ============================================================
# QPS Peak Finder 全流程守护编排脚本
# xinghan-chart-32b-v1-1-agent — Agent 数据集
#
# 自动串行执行 Phase 1 → Phase 2 → Phase 3，
# 并从每阶段输出中提取关键参数传递给下一阶段。
#
# 用法：
#   bash scripts/benchmark/run_peak_finder_chart_agent.sh 8tp
#   bash scripts/benchmark/run_peak_finder_chart_agent.sh 4tp
#
# 断点续跑（从 Phase 2 开始）：
#   START_PHASE=2 PEAK_RPS=X.XXXX START_RPS=X.XXXX \
#     bash scripts/benchmark/run_peak_finder_chart_agent.sh 8tp
#
# 断点续跑（从 Phase 3 开始）：
#   START_PHASE=3 IDEAL_RPS=X.XXXX \
#     bash scripts/benchmark/run_peak_finder_chart_agent.sh 8tp
#
# 环境变量（可选）：
#   START_PHASE   从哪个阶段开始，默认 1
#   PEAK_RPS      Phase 1 结果（START_PHASE≥2 时必填）
#   START_RPS     Phase 2 起始 QPS（START_PHASE≥2 时必填）
#   IDEAL_RPS     Phase 2 结果（START_PHASE=3 时必填）
#   INIT_CON      Phase 1 起始并发（可选）
#   INIT_LO       Phase 2 续跑 bracket LO（可选）
#   INIT_HI       Phase 2 续跑 bracket HI（可选）
# ============================================================

set -euo pipefail

TP="${1:-8tp}"

if [[ "${TP}" != "8tp" && "${TP}" != "4tp" ]]; then
    echo "❌ 用法: $0 [8tp|4tp]"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BENCH_DIR="${PROJECT_DIR}/scripts/benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"

PHASE1_SCRIPT="${BENCH_DIR}/run_phase1_auto_chart_agent_${TP}.sh"
PHASE2_SCRIPT="${BENCH_DIR}/run_phase2_auto_chart_agent_${TP}.sh"
PHASE3_SCRIPT="${BENCH_DIR}/run_phase3_grid_chart_agent_${TP}.sh"

# ── 会话目录（所有日志汇聚于此）────────────────────────────
TIMESTAMP="$(date +%Y%m%d_%H%M)"
SESSION_DIR="${PROJECT_DIR}/logs/xinghan-chart-32b-v1-1-agent/chart-32b-agent-${TP}-session_${TIMESTAMP}"
mkdir -p "${SESSION_DIR}"

ORCHESTRATOR_LOG="${SESSION_DIR}/orchestrator.log"
STATE_FILE="${SESSION_DIR}/state.env"   # 跨阶段持久化关键变量

# ── 续跑控制 ────────────────────────────────────────────────
START_PHASE="${START_PHASE:-1}"
PEAK_RPS="${PEAK_RPS:-}"
START_RPS="${START_RPS:-}"
IDEAL_RPS="${IDEAL_RPS:-}"

# ── 工具函数 ─────────────────────────────────────────────────
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "${msg}" | tee -a "${ORCHESTRATOR_LOG}"
}

die() {
    log "❌ 致命错误: $*"
    exit 1
}

save_state() {
    # 将关键变量写入 state.env，方便手动续跑时参考
    cat > "${STATE_FILE}" <<EOF
# $(date '+%Y-%m-%d %H:%M:%S') 自动生成，可作为断点续跑参数参考
PEAK_RPS="${PEAK_RPS:-}"
START_RPS="${START_RPS:-}"
IDEAL_RPS="${IDEAL_RPS:-}"
EOF
    log "  状态已保存 → ${STATE_FILE}"
}

# ── 参数验证 ─────────────────────────────────────────────────
if [[ "${START_PHASE}" -ge 2 ]]; then
    [[ -z "${PEAK_RPS}" || -z "${START_RPS}" ]] && \
        die "START_PHASE≥2 时必须设置 PEAK_RPS 和 START_RPS"
fi
if [[ "${START_PHASE}" -ge 3 ]]; then
    [[ -z "${IDEAL_RPS}" ]] && \
        die "START_PHASE=3 时必须设置 IDEAL_RPS"
fi

# ============================================================
log "========================================================"
log "  QPS Peak Finder 全流程编排  —  chart-32b-agent ${TP}"
log "  从 Phase ${START_PHASE} 开始"
log "  会话目录: ${SESSION_DIR}"
log "========================================================"

# ============================================================
# Phase 1：饱和探测
# ============================================================
if [[ "${START_PHASE}" -le 1 ]]; then
    log ""
    log "════════════════════════════════════════"
    log "  Phase 1 启动  (饱和探测)"
    log "════════════════════════════════════════"

    PHASE1_LOG="${SESSION_DIR}/phase1.log"

    # 运行并实时输出到控制台 + 日志文件
    INIT_CON="${INIT_CON:-}" \
    bash "${PHASE1_SCRIPT}" 2>&1 | tee "${PHASE1_LOG}" || \
        die "Phase 1 执行失败（退出码 $?）"

    # 从输出中提取 PEAK_RPS 和 START_RPS
    PEAK_RPS=$(grep -oP 'PEAK_RPS=\K[\d.]+' "${PHASE1_LOG}" | tail -1)
    START_RPS=$(grep -oP 'START_RPS=\K[\d.]+' "${PHASE1_LOG}" | tail -1)

    if [[ -z "${PEAK_RPS}" || -z "${START_RPS}" ]]; then
        die "无法从 Phase 1 输出中提取 PEAK_RPS / START_RPS，请检查 ${PHASE1_LOG}"
    fi

    log ""
    log "  ✅ Phase 1 完成"
    log "     PEAK_RPS  = ${PEAK_RPS} req/s"
    log "     START_RPS = ${START_RPS} req/s（Phase 2 起始，= PEAK_RPS × 1.2）"
    save_state
fi

# ============================================================
# Phase 2：自适应逼近
# ============================================================
if [[ "${START_PHASE}" -le 2 ]]; then
    log ""
    log "════════════════════════════════════════"
    log "  Phase 2 启动  (自适应逼近)"
    log "  PEAK_RPS=${PEAK_RPS}  START_RPS=${START_RPS}"
    log "════════════════════════════════════════"

    PHASE2_LOG="${SESSION_DIR}/phase2.log"

    PEAK_RPS="${PEAK_RPS}" \
    START_RPS="${START_RPS}" \
    INIT_LO="${INIT_LO:-}" \
    INIT_HI="${INIT_HI:-}" \
    bash "${PHASE2_SCRIPT}" 2>&1 | tee "${PHASE2_LOG}" || \
        die "Phase 2 执行失败（退出码 $?）"

    # 从输出中提取 IDEAL_RPS
    IDEAL_RPS=$(grep -oP 'IDEAL_RPS=\K[\d.]+' "${PHASE2_LOG}" | tail -1)

    # 兜底：若打印格式为 "ideal_rps = X.XXXX req/s"
    if [[ -z "${IDEAL_RPS}" ]]; then
        IDEAL_RPS=$(grep -oP 'ideal_rps\s*=\s*\K[\d.]+' "${PHASE2_LOG}" | tail -1)
    fi

    if [[ -z "${IDEAL_RPS}" ]]; then
        die "无法从 Phase 2 输出中提取 IDEAL_RPS，请检查 ${PHASE2_LOG}"
    fi

    log ""
    log "  ✅ Phase 2 完成"
    log "     IDEAL_RPS = ${IDEAL_RPS} req/s"
    save_state
fi

# ============================================================
# Phase 3：上线验证网格
# ============================================================
log ""
log "════════════════════════════════════════"
log "  Phase 3 启动  (上线验证网格)"
log "  IDEAL_RPS=${IDEAL_RPS}"
log "════════════════════════════════════════"

PHASE3_LOG="${SESSION_DIR}/phase3.log"

IDEAL_RPS="${IDEAL_RPS}" \
bash "${PHASE3_SCRIPT}" 2>&1 | tee "${PHASE3_LOG}" || \
    die "Phase 3 执行失败（退出码 $?）"

# ============================================================
log ""
log "========================================================"
log "  🎉 全流程完成！"
log ""
log "  PEAK_RPS  = ${PEAK_RPS} req/s"
log "  IDEAL_RPS = ${IDEAL_RPS} req/s"
log "  会话日志  = ${SESSION_DIR}/"
log ""
log "  下一步："
log "  用 qps-peak-finder-analysis Skill 合并 Phase 2+3 结果生成 REPORT.md"
log "========================================================"
