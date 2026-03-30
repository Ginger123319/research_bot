#!/bin/bash
# Phase 2 → Phase 3 自动衔接监控 — xinghan-guoxue-72b-v1-2-reason EAGLE3 (8×L20)
#
# 用法：
#   PHASE2_DIR=<phase2输出目录> bash scripts/benchmark/watch_and_relay_guoxue_eagle3_l20.sh
#   （后台运行时使用 nohup ... &）
#
# 功能：每 60s 轮询 Phase 2 输出目录下的 phase2_checkpoint.md，
#       一旦出现则解析 ideal_rps，自动启动 Phase 3。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PHASE2_DIR="${PHASE2_DIR:-}"
if [[ -z "${PHASE2_DIR}" ]]; then
    # 自动取最新的 eagle3 Phase 2 目录（非 4h20）
    PHASE2_DIR=$(ls -dt "${PROJECT_DIR}"/logs/guoxue-v2-eagle3-phase2_*/  2>/dev/null | grep -v "4h20" | head -1)
fi

if [[ -z "${PHASE2_DIR}" ]]; then
    echo "❌ 未找到 Phase 2 输出目录，请手动指定 PHASE2_DIR"
    exit 1
fi

CHECKPOINT="${PHASE2_DIR%/}/phase2_checkpoint.md"
RELAY_LOG="${PROJECT_DIR}/logs/relay_eagle3_l20_$(date +%Y%m%d_%H%M).log"
PHASE3_LOG="${PROJECT_DIR}/logs/data-pipeline/eagle3_l20_phase3_$(date +%Y%m%d_%H%M).log"

echo "========================================================"
echo "  Phase 2 → Phase 3 自动衔接监控 (EAGLE3 8×L20)"
echo "  Phase 2 目录: ${PHASE2_DIR}"
echo "  等待 checkpoint: ${CHECKPOINT}"
echo "  relay 日志: ${RELAY_LOG}"
echo "========================================================"

exec > >(tee -a "${RELAY_LOG}") 2>&1

POLL_INTERVAL=60  # 每 60 秒检查一次

while true; do
    TS=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ -f "${CHECKPOINT}" ]]; then
        echo "[${TS}] ✅ checkpoint 已出现: ${CHECKPOINT}"

        # 解析 ideal_rps
        IDEAL_RPS=$(grep -oP '\*\*\K[0-9]+\.[0-9]+(?= req/s\*\*)' "${CHECKPOINT}" | head -1)
        if [[ -z "${IDEAL_RPS}" ]]; then
            # 备用匹配
            IDEAL_RPS=$(grep -oP 'ideal_rps\s*[|:]\s*\K[0-9]+\.[0-9]+' "${CHECKPOINT}" | head -1)
        fi
        if [[ -z "${IDEAL_RPS}" ]]; then
            IDEAL_RPS=$(awk '/ideal_rps/{match($0,/[0-9]+\.[0-9]+/,a); if(a[0]!="") print a[0]}' "${CHECKPOINT}" | head -1)
        fi

        echo "[${TS}]   解析到 ideal_rps = ${IDEAL_RPS}"
        echo "[${TS}]   checkpoint 内容："
        cat "${CHECKPOINT}"
        echo ""

        if [[ -z "${IDEAL_RPS}" ]]; then
            echo "[${TS}] ❌ 无法解析 ideal_rps，请手动检查 checkpoint 并启动 Phase 3"
            exit 1
        fi

        echo "[${TS}] 🚀 启动 Phase 3（IDEAL_RPS=${IDEAL_RPS}，PRODUCTION_RPS=0.195）..."
        echo "[${TS}]   Phase 3 日志: ${PHASE3_LOG}"

        IDEAL_RPS="${IDEAL_RPS}" PRODUCTION_RPS="0.195" \
            nohup bash "${PROJECT_DIR}/scripts/benchmark/run_phase3_grid_guoxue_eagle3.sh" \
            > "${PHASE3_LOG}" 2>&1 &
        PHASE3_PID=$!
        echo "[${TS}] Phase 3 已启动，PID=${PHASE3_PID}"
        echo "[${TS}] 日志: ${PHASE3_LOG}"
        echo "========================================================"
        echo "  relay 完成，监控退出。"
        echo "========================================================"
        exit 0
    fi

    # 显示 Phase 2 进度（最新档位目录）
    LATEST_RPS_DIR=$(ls -dt "${PHASE2_DIR%/}"/rps* 2>/dev/null | head -1 || true)
    if [[ -n "${LATEST_RPS_DIR}" ]]; then
        LATEST_TAG=$(basename "${LATEST_RPS_DIR}")
        LATEST_CSV=$(ls "${LATEST_RPS_DIR}"/*.csv 2>/dev/null | grep -v argv | head -1 || true)
        if [[ -n "${LATEST_CSV}" ]]; then
            N=$(wc -l < "${LATEST_CSV}" 2>/dev/null || echo "?")
            echo "[${TS}]   Phase 2 进行中... 最新档: ${LATEST_TAG}，CSV 行数: ${N}"
        else
            echo "[${TS}]   Phase 2 进行中... 最新档: ${LATEST_TAG}（CSV 尚未生成）"
        fi
    else
        echo "[${TS}]   Phase 2 进行中，等待首档输出..."
    fi

    sleep "${POLL_INTERVAL}"
done
