#!/bin/bash
# Phase 1 → Phase 2 → Phase 3 全自动接力监控 — chart-deep-v5-2-235B 8×H20
#
# 功能：
#   1. 轮询等待 Phase 1 checkpoint（phase1_checkpoint.md）
#   2. 解析 max_rps_estimate → 自动启动 Phase 2
#   3. 轮询等待 Phase 2 checkpoint（phase2_checkpoint.md）
#   4. 解析 ideal_rps → 自动启动 Phase 3
#
# 用法：
#   # 自动定位最新 Phase 1 目录（推荐，与正在运行的 Phase 1 配合）
#   nohup bash scripts/benchmark/watch_and_relay_chart_deep_8h20.sh \
#       > logs/chart-deep-v5-2/relay_$(date +%Y%m%d_%H%M).log 2>&1 &
#
#   # 手动指定 Phase 1 目录（续跑或恢复）
#   PHASE1_DIR=logs/chart-deep-v5-2/chart-deep-v5-2-phase1_20260326_1149 \
#     nohup bash scripts/benchmark/watch_and_relay_chart_deep_8h20.sh ... &

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"

PHASE2_SCRIPT="${PROJECT_DIR}/scripts/benchmark/run_phase2_auto_chart_deep_8h20.sh"
PHASE3_SCRIPT="${PROJECT_DIR}/scripts/benchmark/run_phase3_grid_chart_deep_8h20.sh"
PRODUCTION_RPS="${PRODUCTION_RPS:-0.5}"
POLL_INTERVAL=60   # 每 60s 检查一次

# ── 定位 Phase 1 目录 ───────────────────────────────────────────────
PHASE1_DIR="${PHASE1_DIR:-}"
if [[ -z "${PHASE1_DIR}" ]]; then
    PHASE1_DIR=$(ls -dt "${PROJECT_DIR}"/logs/chart-deep-v5-2/chart-deep-v5-2-phase1_* 2>/dev/null | head -1)
fi
if [[ -z "${PHASE1_DIR}" ]]; then
    echo "❌ 未找到 Phase 1 输出目录，请手动指定 PHASE1_DIR"
    exit 1
fi

PHASE1_CHECKPOINT="${PHASE1_DIR%/}/phase1_checkpoint.md"
RELAY_LOG="${PROJECT_DIR}/logs/chart-deep-v5-2/relay_$(date +%Y%m%d_%H%M).log"

echo "========================================================"
echo "  全自动接力监控 — chart-deep-v5-2-235B 8×H20"
echo "  Phase 1 目录: ${PHASE1_DIR}"
echo "  等待 checkpoint: ${PHASE1_CHECKPOINT}"
echo "  本脚本日志: ${RELAY_LOG}"
echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

# ══════════════════════════════════════════════════════════════
# 阶段一：等待 Phase 1 完成
# ══════════════════════════════════════════════════════════════
echo ""
echo "▶ 阶段一：等待 Phase 1 饱和探测完成..."

while true; do
    TS=$(date '+%H:%M:%S')

    # Bug 1 修复：仅在 Phase 1 完全结束后才 break
    # 检测 Phase 1 run log 是否出现完成标志
    PHASE1_RUN_LOG=$(ls -t "${PROJECT_DIR}"/logs/chart-deep-v5-2/phase1_run_*.log 2>/dev/null | head -1 || true)
    PHASE1_DONE=false
    if [[ -f "${PHASE1_CHECKPOINT}" ]]; then
        if [[ -n "${PHASE1_RUN_LOG}" ]] && grep -q "Phase 1 全部档位完成\|NEXT_CON=SATURATED" "${PHASE1_RUN_LOG}" 2>/dev/null; then
            PHASE1_DONE=true
        elif [[ -f "${PHASE1_DIR%/}/phase1_done" ]]; then
            PHASE1_DONE=true
        fi
    fi

    if [[ "${PHASE1_DONE}" == "true" ]]; then
        echo "[${TS}] ✅ Phase 1 全部档位完成，checkpoint 已就绪"
        echo ""
        cat "${PHASE1_CHECKPOINT}"
        echo ""
        break
    elif [[ -f "${PHASE1_CHECKPOINT}" ]]; then
        # 检查点已出现但 Phase 1 仍在继续跑后续档
        LATEST_CON_DIR=$(ls -dt "${PHASE1_DIR%/}"/con* 2>/dev/null | head -1 || true)
        CON_TAG=$(basename "${LATEST_CON_DIR:-unknown}")
        echo "[${TS}]   Phase 1 继续中（checkpoint 已出现，等待饱和判定完成）最新档: ${CON_TAG}"
    fi

    # 显示 Phase 1 当前进度（最新并发档）
    if [[ -z "${LATEST_CON_DIR:-}" ]]; then
        LATEST_CON_DIR=$(ls -dt "${PHASE1_DIR%/}"/con* 2>/dev/null | head -1 || true)
    fi
    if [[ -n "${LATEST_CON_DIR:-}" ]]; then
        CON_TAG=$(basename "${LATEST_CON_DIR}")
        LATEST_CSV=$(ls "${LATEST_CON_DIR}"/*.csv 2>/dev/null | grep -v argv | head -1 || true)
        if [[ -n "${LATEST_CSV}" ]]; then
            N=$(wc -l < "${LATEST_CSV}" 2>/dev/null || echo "?")
            echo "[${TS}]   Phase 1 进行中... 最新档: ${CON_TAG}，CSV 行数: ${N}"
        else
            echo "[${TS}]   Phase 1 进行中... 最新档: ${CON_TAG}（CSV 生成中）"
        fi
    else
        echo "[${TS}]   Phase 1 进行中，等待首档输出..."
    fi

    sleep "${POLL_INTERVAL}"
done

# ── 解析 Phase 1 的 max_rps_estimate ─────────────────────────────
# Bug 2 修复：checkpoint 是 Markdown 表格格式 "| max_rps_estimate | X.XXXX req/s |"
TS=$(date '+%H:%M:%S')
# 取最后一行 max_rps_estimate（最高并发档的值）
PEAK_RPS=$(grep -oP '\|\s*max_rps_estimate\s*\|\s*\K[0-9]+\.[0-9]+' "${PHASE1_CHECKPOINT}" | tail -1 || true)
if [[ -z "${PEAK_RPS}" ]]; then
    # 备用：awk 匹配所有含 max_rps_estimate 的行，取最后一个数字
    PEAK_RPS=$(awk '/max_rps_estimate/{match($0,/[0-9]+\.[0-9]+/,a); if(a[0]!="") print a[0]}' \
               "${PHASE1_CHECKPOINT}" | tail -1)
fi

if [[ -z "${PEAK_RPS}" ]]; then
    echo "[${TS}] ❌ 无法从 Phase 1 checkpoint 解析 max_rps_estimate"
    echo "  请手动执行："
    echo "  PEAK_RPS=<value> START_RPS=<value×1.2> bash ${PHASE2_SCRIPT}"
    exit 1
fi

START_RPS=$(${PYTHON} -c "print(f'{float(\"${PEAK_RPS}\") * 1.2:.4f}')")
echo "[${TS}] 解析到: max_rps_estimate=${PEAK_RPS} → Phase 2 起始 RPS=${START_RPS}"

# ══════════════════════════════════════════════════════════════
# 阶段二：启动 Phase 2 并等待收敛
# ══════════════════════════════════════════════════════════════
echo ""
echo "▶ 阶段二：启动 Phase 2 自动收敛..."

PHASE2_LOG="${PROJECT_DIR}/logs/chart-deep-v5-2/phase2_run_$(date +%Y%m%d_%H%M).log"

PEAK_RPS="${PEAK_RPS}" START_RPS="${START_RPS}" PRODUCTION_RPS="${PRODUCTION_RPS}" \
    nohup bash "${PHASE2_SCRIPT}" > "${PHASE2_LOG}" 2>&1 &
PHASE2_PID=$!
echo "[$(date '+%H:%M:%S')] Phase 2 已启动，PID=${PHASE2_PID}"
echo "  日志: ${PHASE2_LOG}"

# 定位 Phase 2 输出目录（轮询直到目录出现）
echo "[$(date '+%H:%M:%S')] 等待 Phase 2 输出目录创建..."
PHASE2_DIR=""
for i in $(seq 1 30); do
    sleep 10
    PHASE2_DIR=$(ls -dt "${PROJECT_DIR}"/logs/chart-deep-v5-2/chart-deep-v5-2-phase2_* 2>/dev/null | head -1 || true)
    if [[ -n "${PHASE2_DIR}" ]]; then
        echo "[$(date '+%H:%M:%S')] Phase 2 目录: ${PHASE2_DIR}"
        break
    fi
done

if [[ -z "${PHASE2_DIR}" ]]; then
    echo "❌ Phase 2 目录未出现，请检查 ${PHASE2_LOG}"
    exit 1
fi

PHASE2_CHECKPOINT="${PHASE2_DIR%/}/phase2_checkpoint.md"
echo ""
echo "▶ 等待 Phase 2 收敛（checkpoint: ${PHASE2_CHECKPOINT}）..."

while true; do
    TS=$(date '+%H:%M:%S')

    if [[ -f "${PHASE2_CHECKPOINT}" ]]; then
        echo "[${TS}] ✅ Phase 2 checkpoint 已出现"
        echo ""
        cat "${PHASE2_CHECKPOINT}"
        echo ""
        break
    fi

    # 检查 Phase 2 进程是否还在
    if ! kill -0 "${PHASE2_PID}" 2>/dev/null; then
        echo "[${TS}] ⚠️  Phase 2 进程已退出（PID=${PHASE2_PID}），扫描 checkpoint..."
        PHASE2_CHECKPOINT_FALLBACK=$(ls "${PHASE2_DIR%/}"/*.md 2>/dev/null | head -1 || true)
        if [[ -n "${PHASE2_CHECKPOINT_FALLBACK}" && -f "${PHASE2_CHECKPOINT_FALLBACK}" ]]; then
            echo "  找到 fallback checkpoint: ${PHASE2_CHECKPOINT_FALLBACK}"
            PHASE2_CHECKPOINT="${PHASE2_CHECKPOINT_FALLBACK}"
            cat "${PHASE2_CHECKPOINT}"
            echo ""
            break
        fi
        echo "  未找到任何 checkpoint，请手动查看 ${PHASE2_LOG}"
        exit 1
    fi

    # 显示 Phase 2 进度
    LATEST_RPS_DIR=$(ls -dt "${PHASE2_DIR%/}"/rps* 2>/dev/null | head -1 || true)
    if [[ -n "${LATEST_RPS_DIR}" ]]; then
        LATEST_TAG=$(basename "${LATEST_RPS_DIR}")
        LATEST_CSV=$(ls "${LATEST_RPS_DIR}"/*.csv 2>/dev/null | grep -v argv | head -1 || true)
        if [[ -n "${LATEST_CSV}" ]]; then
            N=$(wc -l < "${LATEST_CSV}" 2>/dev/null || echo "?")
            echo "[${TS}]   Phase 2 进行中... 最新档: ${LATEST_TAG}，CSV 行数: ${N}"
        else
            echo "[${TS}]   Phase 2 进行中... 最新档: ${LATEST_TAG}（CSV 生成中）"
        fi
    else
        echo "[${TS}]   Phase 2 进行中，等待首档输出..."
    fi

    sleep "${POLL_INTERVAL}"
done

# ── 解析 Phase 2 的 ideal_rps ─────────────────────────────────────
TS=$(date '+%H:%M:%S')
IDEAL_RPS=$(grep -oP '\*\*\K[0-9]+\.[0-9]+(?= req/s\*\*)' "${PHASE2_CHECKPOINT}" | head -1)
if [[ -z "${IDEAL_RPS}" ]]; then
    IDEAL_RPS=$(grep -oP 'ideal_rps\s*[|:*]+\s*\K[0-9]+\.[0-9]+' "${PHASE2_CHECKPOINT}" | head -1)
fi
if [[ -z "${IDEAL_RPS}" ]]; then
    IDEAL_RPS=$(awk '/ideal_rps/{match($0,/[0-9]+\.[0-9]+/,a); if(a[0]!="") print a[0]}' \
               "${PHASE2_CHECKPOINT}" | head -1)
fi

if [[ -z "${IDEAL_RPS}" ]]; then
    echo "[${TS}] ❌ 无法从 Phase 2 checkpoint 解析 ideal_rps"
    echo "  请手动执行："
    echo "  IDEAL_RPS=<value> PRODUCTION_RPS=${PRODUCTION_RPS} bash ${PHASE3_SCRIPT}"
    exit 1
fi

IDEAL_RPM=$(${PYTHON} -c "print(f'{float(\"${IDEAL_RPS}\")*60:.1f}')")
echo "[${TS}] 解析到: ideal_rps=${IDEAL_RPS}（${IDEAL_RPM} RPM）"

# ══════════════════════════════════════════════════════════════
# 阶段三：启动 Phase 3 验证网格
# ══════════════════════════════════════════════════════════════
echo ""
echo "▶ 阶段三：启动 Phase 3 上线验证网格..."

PHASE3_LOG="${PROJECT_DIR}/logs/chart-deep-v5-2/phase3_run_$(date +%Y%m%d_%H%M).log"

IDEAL_RPS="${IDEAL_RPS}" PRODUCTION_RPS="${PRODUCTION_RPS}" \
    nohup bash "${PHASE3_SCRIPT}" > "${PHASE3_LOG}" 2>&1 &
PHASE3_PID=$!

echo "[$(date '+%H:%M:%S')] Phase 3 已启动，PID=${PHASE3_PID}"
echo "  日志: ${PHASE3_LOG}"

# 等待 Phase 3 完成
echo ""
echo "▶ 等待 Phase 3 完成..."
wait "${PHASE3_PID}" || true

echo ""
echo "========================================================"
echo "✅ 全三段评估流程完成！"
echo "  Phase 1 checkpoint: ${PHASE1_CHECKPOINT}"
echo "  Phase 2 checkpoint: ${PHASE2_CHECKPOINT}"
echo "  Phase 3 日志: ${PHASE3_LOG}"
echo ""
echo "  ▶ 下一步：运行 qps-peak-finder-analysis 技能生成 REPORT.md"
echo "========================================================"
