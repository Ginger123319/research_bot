#!/bin/bash
# 自动衔接脚本：等待 4TP Phase 2 收敛 → 提取 ideal_rps → 启动 Phase 3
#
# 用法：
#   bash scripts/benchmark/run_phase3_auto_chart4tp.sh
#
# 说明：
#   - 每 30s 轮询 Phase 2 日志，检测 "Phase 2a 收敛完成" 关键字
#   - 从日志中提取 ideal_rps
#   - 自动调用 run_phase3_grid_chart4tp.sh

set -uo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"

# Phase 2 续跑日志（固定路径）
PHASE2_LOG="${PROJECT_DIR}/logs/phase2_chart4tp_resume_20260319.log"
POLL_INTERVAL=30   # 秒

echo "========================================================"
echo "4TP Phase 3 自动衔接 — 等待 Phase 2 收敛"
echo "  监听日志: ${PHASE2_LOG}"
echo "  轮询间隔: ${POLL_INTERVAL}s"
echo "  启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

# 等待 Phase 2 收敛
while true; do
    if [[ ! -f "${PHASE2_LOG}" ]]; then
        echo "  ⏳ 日志尚未创建，等待 ${POLL_INTERVAL}s ..."
        sleep "${POLL_INTERVAL}"
        continue
    fi

    if grep -q "Phase 2a 收敛完成" "${PHASE2_LOG}"; then
        # 提取 ideal_rps（取最后一次出现的值）
        IDEAL_RPS=$(grep "ideal_rps = " "${PHASE2_LOG}" | grep -oP '[0-9]+\.[0-9]+' | tail -1)
        if [[ -z "${IDEAL_RPS}" ]]; then
            echo "  ⚠️  检测到收敛关键字但无法解析 ideal_rps，等待 ${POLL_INTERVAL}s 重试..."
            sleep "${POLL_INTERVAL}"
            continue
        fi
        echo ""
        echo "  ✅ Phase 2 已收敛！ideal_rps = ${IDEAL_RPS} req/s"
        echo "  → 启动 Phase 3 ($(date '+%Y-%m-%d %H:%M:%S'))"
        break
    fi

    # 打印当前 Phase 2 最新状态（最后一行有意义的输出）
    LAST_STATUS=$(grep -E "bracket|档|rps|SLA|收敛" "${PHASE2_LOG}" 2>/dev/null | tail -1)
    echo "  ⏳ Phase 2 进行中... [$(date '+%H:%M:%S')]  ${LAST_STATUS}"
    sleep "${POLL_INTERVAL}"
done

# 启动 Phase 3
echo ""
IDEAL_RPS="${IDEAL_RPS}" bash "${PROJECT_DIR}/scripts/benchmark/run_phase3_grid_chart4tp.sh"
