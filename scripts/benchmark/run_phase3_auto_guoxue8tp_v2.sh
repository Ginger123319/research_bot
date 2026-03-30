#!/bin/bash
# Phase 3 自动衔接器 — xinghan-guoxue-72b-v1-2-reason 8×L20 V2
#
# 功能：轮询 Phase 2 目录，检测到收敛 checkpoint 后自动启动 Phase 3。
# 无需人工守候，后台运行即可。
#
# 用法：
#   # 自动检测最新 Phase 2 目录
#   nohup bash scripts/benchmark/run_phase3_auto_guoxue8tp_v2.sh \
#     > logs/phase3_auto_guoxue8tp_v2_$(date +%Y%m%d_%H%M).log 2>&1 &
#
#   # 指定 Phase 2 目录
#   PHASE2_DIR=logs/guoxue-v2-phase2_20260320_1920 \
#   nohup bash scripts/benchmark/run_phase3_auto_guoxue8tp_v2.sh \
#     > logs/phase3_auto_guoxue8tp_v2_$(date +%Y%m%d_%H%M).log 2>&1 &

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASE3_SCRIPT="${PROJECT_DIR}/scripts/benchmark/run_phase3_grid_guoxue8tp_v2.sh"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

PRODUCTION_RPS=0.05   # 与 Phase 2 保持一致
TTFS_P90_LIMIT=1.5
E2E_P90_LIMIT=180.0
PHASE2_SCRIPT_NAME="run_phase2_auto_guoxue8tp_v2"   # 用于进程死亡检测
POLL_INTERVAL=300     # 每 5 分钟轮询一次
MAX_WAIT_HOURS=24     # 最多等待 24 小时
MAX_POLLS=$(( MAX_WAIT_HOURS * 3600 / POLL_INTERVAL ))

# ── 确定监视目录 ──────────────────────────────────────────────
if [[ -n "${PHASE2_DIR:-}" ]]; then
    WATCH_DIR="${PROJECT_DIR}/${PHASE2_DIR}"
else
    # 自动找最新的 Phase 2 目录
    WATCH_DIR=$(ls -dt "${PROJECT_DIR}/logs/guoxue-v2-phase2_"* 2>/dev/null | head -1)
fi

if [[ -z "${WATCH_DIR}" || ! -d "${WATCH_DIR}" ]]; then
    echo "❌ 找不到 Phase 2 输出目录，请先启动 Phase 2 或手动指定 PHASE2_DIR"
    exit 1
fi

CHECKPOINT="${WATCH_DIR}/phase2_checkpoint.md"

echo "========================================================"
echo "Phase 3 自动衔接器 — guoxue-72b V2 8×L20"
echo "  监视目录: ${WATCH_DIR}"
echo "  检查点:   ${CHECKPOINT}"
echo "  轮询间隔: ${POLL_INTERVAL}s（每 $(( POLL_INTERVAL / 60 ))min 检查一次）"
echo "  最大等待: ${MAX_WAIT_HOURS}h"
echo "  启动时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
echo ""

# ── 等待 Phase 2 收敛 ─────────────────────────────────────────
IDEAL_RPS=""

for poll in $(seq 1 ${MAX_POLLS}); do
    ELAPSED_MIN=$(( (poll - 1) * POLL_INTERVAL / 60 ))
    echo "[$(date '+%H:%M:%S')] 第 ${poll} 次检查（已等待 ${ELAPSED_MIN}min）..."

    # ── 方式1：bracket 收敛，checkpoint 文件存在 ──
    if [[ -f "${CHECKPOINT}" ]]; then
        echo "  ✅ 检测到 phase2_checkpoint.md，Phase 2 已收敛！"
        cat "${CHECKPOINT}"

        # 从 checkpoint 提取 ideal_rps
        IDEAL_RPS=$(grep -oP 'IDEAL_RPS=\K[\d.]+' "${CHECKPOINT}" | head -1)
        if [[ -n "${IDEAL_RPS}" ]]; then
            echo ""
            echo "  📌 提取到 ideal_rps = ${IDEAL_RPS} req/s"
            break
        else
            echo "  ⚠️ 无法从 checkpoint 提取 ideal_rps，手动检查文件"
            cat "${CHECKPOINT}"
            exit 1
        fi
    fi

    # ── 方式2：Phase 2 进程已退出，无 checkpoint → 扫描 rps* 推断 ideal_rps ──
    # 至少等待 3 次轮询（15min）后才检测，避免 Phase 2 刚启动时误触发
    if [[ ${poll} -ge 3 ]]; then
        PHASE2_PROC=$(ps aux | grep "${PHASE2_SCRIPT_NAME}" | grep -v grep | wc -l)
        if [[ "${PHASE2_PROC}" -eq 0 ]]; then
            echo "  📡 未检测到 Phase 2 进程（${PHASE2_SCRIPT_NAME}），尝试自主推断 ideal_rps..."
            RECOVERY_BEST=""
            for rdir in $(ls -d "${WATCH_DIR}"/rps* 2>/dev/null | sort); do
                if ls "${rdir}"/*.csv 2>/dev/null | grep -qv "argv" 2>/dev/null; then
                    SLA_RESULT=$(${PYTHON} "${ANALYZE}" \
                        --phase 2 --dir "${rdir}" \
                        --ttfs-p90-limit "${TTFS_P90_LIMIT}" \
                        --e2e-p90-limit "${E2E_P90_LIMIT}" \
                        2>/dev/null \
                        | grep -oP '\[SLA_(PASS|FAIL)\]' \
                        | grep -oP 'PASS|FAIL' || echo "UNKNOWN")
                    RPS_VAL=$(basename "${rdir}" | grep -oP 'rps\K[\d.]+' || echo "")
                    echo "    $(basename ${rdir}) → ${SLA_RESULT}"
                    if [[ "${SLA_RESULT}" == "PASS" && -n "${RPS_VAL}" ]]; then
                        RECOVERY_BEST="${RPS_VAL}"
                    fi
                fi
            done
            if [[ -n "${RECOVERY_BEST}" ]]; then
                IDEAL_RPS="${RECOVERY_BEST}"
                echo ""
                echo "  ✅ 自主推断 ideal_rps = ${IDEAL_RPS} req/s（最高 PASS 轮）"
                cat > "${WATCH_DIR}/phase2_recovery_checkpoint.md" << EOF
# Phase 2 恢复检查点 [RECOVERY]

> ⚠️ Phase 2 进程退出后未写入 checkpoint，由衔接脚本扫描 rps* 目录自动推断。

| 指标 | 值 |
|------|-----|
| **ideal_rps** | **${IDEAL_RPS} req/s** |
| **ideal_rpm** | $(${PYTHON} -c "print(f'{float(\"${IDEAL_RPS}\")*60:.1f}')") RPM |
| 来源 | RECOVERY（Phase 3 衔接脚本自动推断）|
| SLA | TTFS P90 ≤ ${TTFS_P90_LIMIT}s，E2E P90 ≤ ${E2E_P90_LIMIT}s |
EOF
                break
            else
                echo "  ⚠️ 扫描完毕，无任何 PASS 轮次，继续等待或手动干预"
            fi
        fi
    fi

    echo "  ⏳ Phase 2 仍在运行，下次检查在 $(( POLL_INTERVAL / 60 ))min 后..."
    sleep ${POLL_INTERVAL}
done

# ── Phase 2 收敛结果验证 ──────────────────────────────────────
if [[ -z "${IDEAL_RPS}" ]]; then
    echo ""
    echo "❌ 等待超时（${MAX_WAIT_HOURS}h），未检测到 Phase 2 收敛。"
    echo "   请手动检查 Phase 2 状态后执行 Phase 3："
    echo "   IDEAL_RPS=<value> PRODUCTION_RPS=${PRODUCTION_RPS} bash ${PHASE3_SCRIPT}"
    exit 1
fi

echo ""
echo "========================================================"
echo "Phase 2 收敛确认"
echo "  ideal_rps      = ${IDEAL_RPS} req/s"
echo "  ideal_rpm      = $(${PYTHON} -c "print(f'{float(\"${IDEAL_RPS}\")*60:.1f}')") RPM"
echo "  production_rps = ${PRODUCTION_RPS} req/s"
echo ""

# 计算 Phase 3 档位预览（linspace 4 点）
echo "Phase 3 档位预览（linspace 4 点）："
${PYTHON} -c "
import numpy as np
lo, hi = float('${PRODUCTION_RPS}'), float('${IDEAL_RPS}')
levels = np.linspace(lo, hi, 4)
for i, v in enumerate(levels, 1):
    print(f'  档位{i}: {v:.4f} req/s  ({v*60:.1f} RPM)')
"
echo ""
echo "  DURATION_SECS = 3600s（1h/档）"
echo "  COOLDOWN_SECS = 900s（15min）"
echo "  预计总时长: ~$(( 4 * (3600 + 900) / 3600 ))h30min"
echo "========================================================"
echo ""

# ── 等待服务冷却后再启动 Phase 3 ────────────────────────────────
# Phase 2 最后一轮刚结束，先等满 1 个冷却周期，确保服务完全空闲
PRECOOL=900
echo "⏳ Phase 2 刚结束，预冷却 ${PRECOOL}s（${PRECOOL}s = 15min）后启动 Phase 3..."
echo "   Phase 3 预计启动时间: $(date -d "+${PRECOOL} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v +${PRECOOL}S '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '约 15min 后')"
sleep ${PRECOOL}

# ── 启动 Phase 3 ─────────────────────────────────────────────
echo ""
echo "========================================================"
echo "🚀 启动 Phase 3！"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
echo ""

IDEAL_RPS="${IDEAL_RPS}" \
PRODUCTION_RPS="${PRODUCTION_RPS}" \
  bash "${PHASE3_SCRIPT}"
