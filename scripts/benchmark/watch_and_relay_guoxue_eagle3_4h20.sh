#!/bin/bash
# 监控 Phase 1 完成，自动读取 checkpoint 并启动 Phase 2
# Eagle3 4×H20 专用
#
# 用法：
#   bash scripts/benchmark/watch_and_relay_guoxue_eagle3_4h20.sh &
#
# 功能：
#   1. 每 60s 轮询 Phase 1 输出目录，检测 phase1_checkpoint.md 是否生成
#   2. checkpoint 出现后，解析 PEAK_RPS 和 START_RPS
#   3. 自动启动 Phase 2（run_phase2_auto_guoxue_eagle3_4h20.sh）
#   4. 全程写入 relay_log

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
PHASE1_LOG="${PROJECT_DIR}/logs/phase1_eagle3_4h20_console.log"
PHASE2_SCRIPT="${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_guoxue_eagle3_4h20.sh"
RELAY_LOG="${PROJECT_DIR}/logs/relay_eagle3_4h20_$(date +%Y%m%d_%H%M).log"

# Phase 1 输出目录（从启动日志提取）
PHASE1_BASE=$(grep -oP '输出目录: \K.*' "${PHASE1_LOG}" 2>/dev/null | head -1 || echo "")
if [[ -z "${PHASE1_BASE}" ]]; then
    # fallback：找最新的 eagle3-4h20-phase1 目录
    PHASE1_BASE=$(ls -dt "${PROJECT_DIR}/logs"/guoxue-v2-eagle3-4h20-phase1_* 2>/dev/null | head -1 || echo "")
fi

CHECKPOINT="${PHASE1_BASE}/phase1_checkpoint.md"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${RELAY_LOG}"
}

log "=========================================================="
log "Phase 1 → Phase 2 自动衔接监控启动"
log "  Phase 1 输出目录: ${PHASE1_BASE}"
log "  等待 checkpoint: ${CHECKPOINT}"
log "  Phase 2 脚本: ${PHASE2_SCRIPT}"
log "  relay 日志: ${RELAY_LOG}"
log "=========================================================="

MAX_WAIT_HOURS=24
POLL_INTERVAL=60
ELAPSED=0
MAX_WAIT_SECS=$((MAX_WAIT_HOURS * 3600))

while true; do
    if [[ -f "${CHECKPOINT}" ]]; then
        log "✅ phase1_checkpoint.md 已出现！"
        break
    fi

    ELAPSED=$((ELAPSED + POLL_INTERVAL))
    if [[ ${ELAPSED} -ge ${MAX_WAIT_SECS} ]]; then
        log "❌ 等待超过 ${MAX_WAIT_HOURS}h，放弃自动衔接"
        exit 1
    fi

    # 每 10 分钟报告一次 Phase 1 进度
    if (( ELAPSED % 600 == 0 )); then
        PHASE1_PID=$(pgrep -f "run_phase1_auto_guoxue_eagle3_4h20" 2>/dev/null || echo "")
        if [[ -n "${PHASE1_PID}" ]]; then
            LATEST_LINE=$(tail -3 "${PHASE1_LOG}" 2>/dev/null | grep -v "^$" | tail -1 || echo "")
            log "  Phase 1 进行中（PID ${PHASE1_PID}）: ${LATEST_LINE}"
        else
            log "  ⚠️ Phase 1 进程未找到（可能已完成或异常退出），继续等待 checkpoint..."
        fi
    fi

    sleep ${POLL_INTERVAL}
done

# ── 解析 checkpoint ──────────────────────────────────────────
log ""
log "── 解析 phase1_checkpoint.md ──"
cat "${CHECKPOINT}" | tee -a "${RELAY_LOG}"
log ""

# 提取 max_rps_estimate（PEAK_RPS）
PEAK_RPS=$(grep -oP '\|\s*max_rps_estimate\s*\|[^|]*\|\s*$' "${CHECKPOINT}" | \
           grep -oP '[\d.]+(?=\s*req/s)' | head -1 || echo "")

# 提取 Phase 2 起始 QPS（START_RPS）
START_RPS=$(grep -oP 'Phase 2 起始 QPS.*?\*\*\K[\d.]+(?=\s*req/s)' "${CHECKPOINT}" | head -1 || \
            grep -oP 'PEAK_RPS=\K[\d.]+' "${CHECKPOINT}" | head -1 || echo "")

# 兜底：若正则未匹配，从 checkpoint 的 "Phase 2 启动命令" 代码块里提取
if [[ -z "${PEAK_RPS}" ]]; then
    PEAK_RPS=$(grep -oP 'PEAK_RPS=\K[\d.]+' "${CHECKPOINT}" | head -1 || echo "")
fi
if [[ -z "${START_RPS}" ]]; then
    START_RPS=$(grep -oP 'START_RPS=\K[\d.]+' "${CHECKPOINT}" | head -1 || echo "")
fi

if [[ -z "${PEAK_RPS}" || -z "${START_RPS}" ]]; then
    log "❌ 无法从 checkpoint 解析 PEAK_RPS 或 START_RPS，请手动启动 Phase 2"
    log "   checkpoint 内容已打印在上方"
    log "   手动命令："
    log "     PEAK_RPS=<值> START_RPS=<值> bash ${PHASE2_SCRIPT}"
    exit 1
fi

log "  PEAK_RPS=${PEAK_RPS}  START_RPS=${START_RPS}"
log ""

# ── 等待 Phase 1 进程完全退出（确保日志和 CSV 均已落盘）──────────
PHASE1_PID=$(pgrep -f "run_phase1_auto_guoxue_eagle3_4h20" 2>/dev/null || echo "")
if [[ -n "${PHASE1_PID}" ]]; then
    log "Phase 1 进程 PID=${PHASE1_PID} 仍在运行（checkpoint 写完后通常很快退出），等待 30s..."
    sleep 30
fi

log ""
log "=========================================================="
log "▶ 启动 Phase 2："
log "   PEAK_RPS=${PEAK_RPS} START_RPS=${START_RPS} bash ${PHASE2_SCRIPT}"
log "=========================================================="

# ── 启动 Phase 2 ─────────────────────────────────────────────
PHASE2_LOG="${PROJECT_DIR}/logs/phase2_eagle3_4h20_console.log"
nohup env PEAK_RPS="${PEAK_RPS}" START_RPS="${START_RPS}" \
    bash "${PHASE2_SCRIPT}" \
    > "${PHASE2_LOG}" 2>&1 &

PHASE2_PID=$!
log "Phase 2 已启动，PID=${PHASE2_PID}"
log "Phase 2 日志: ${PHASE2_LOG}"
log ""
log "监控命令："
log "  tail -f ${PHASE2_LOG}"
