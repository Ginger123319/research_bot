#!/bin/bash
# ============================================================
# datas/ → /mnt/ai-infra/datasets/used4evaluation/ 迁移脚本
#
# 执行效果：
#   1. 将 datas/ 下所有实体文件/目录移动到 used4evaluation/
#      对应模型子目录下
#   2. 在 datas/ 原位置创建软链接，路径对外完全透明
#
# 前置条件：
#   - chart-32b benchmark (Phase 1~3) 已全部完成
#
# 用法：
#   bash scripts/migrate_datas_to_used4evaluation.sh
#   （约需 2~5 分钟，依赖同一文件系统 mv 速度）
# ============================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATAS_DIR="${PROJECT_DIR}/datas"
TARGET_BASE="/mnt/ai-infra/datasets/used4evaluation"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "❌ $*" >&2; exit 1; }

# ── 安全检查 ─────────────────────────────────────────────────
log "检查 benchmark 进程是否已全部退出..."
if pgrep -f "run_peak_finder_chart_agent" > /dev/null 2>&1; then
    die "编排脚本仍在运行，请等待 benchmark 完成后再迁移！"
fi
if pgrep -f "infra-xinghan-chart-p32b" > /dev/null 2>&1; then
    die "benchmark 请求进程仍在运行，请等待完成后再迁移！"
fi
log "✅ 无活跃 benchmark 进程，可以安全迁移"

# ── 辅助函数：移动并建软链 ────────────────────────────────────
move_and_link() {
    local src="$1"   # datas/ 内原路径（绝对）
    local dst="$2"   # used4evaluation/ 内目标路径（绝对）

    if [[ ! -e "${src}" && ! -L "${src}" ]]; then
        log "  ⚠️  跳过（不存在）: ${src##*/}"
        return
    fi
    if [[ -L "${src}" ]]; then
        log "  ⚠️  已是软链接，跳过: ${src##*/}"
        return
    fi

    log "  mv  ${src##*/} → ${dst}"
    mv "${src}" "${dst}"
    ln -s "${dst}" "${src}"
    log "  ✅  链接已建立"
}

# ============================================================
# 1. 创建目标子目录
# ============================================================
log "创建 used4evaluation 子目录..."
mkdir -p "${TARGET_BASE}/xinghan-chart-32b-v1-1-agent"
mkdir -p "${TARGET_BASE}/xinghan-guoxue-72b-v1-2-reason"
mkdir -p "${TARGET_BASE}/xinghan-ziwei-32b-v1-1"
mkdir -p "${TARGET_BASE}/tianji-querysafety-4b-v2-3"
mkdir -p "${TARGET_BASE}/xinghan-hepan-72b-v1-2"
mkdir -p "${TARGET_BASE}/lingyu-235b-A22b-v9-2"

# ============================================================
# 2. xinghan-chart-32b-v1-1-agent — 源文件
# ============================================================
log ""
log "── chart-32b：源文件 ──"
for f in \
    xinghan-chart-32b-v1-1-agent_260312_260316.jsonl \
    xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl \
    xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl \
    xinghan-chart-32b-v1-1-agent_calls_converted.jsonl; do
    move_and_link \
        "${DATAS_DIR}/${f}" \
        "${TARGET_BASE}/xinghan-chart-32b-v1-1-agent/${f}"
done

log ""
log "── chart-32b：output 目录 ──"
move_and_link \
    "${DATAS_DIR}/output_chart" \
    "${TARGET_BASE}/xinghan-chart-32b-v1-1-agent/output_chart"
move_and_link \
    "${DATAS_DIR}/output_chart_agent" \
    "${TARGET_BASE}/xinghan-chart-32b-v1-1-agent/output_chart_agent"

# ============================================================
# 3. xinghan-guoxue-72b-v1-2-reason
# ============================================================
log ""
log "── guoxue：源文件 ──"
move_and_link \
    "${DATAS_DIR}/xinghan-guoxue-72b-v1-2-reason_260313_260314.jsonl" \
    "${TARGET_BASE}/xinghan-guoxue-72b-v1-2-reason/xinghan-guoxue-72b-v1-2-reason_260313_260314.jsonl"

log ""
log "── guoxue：output 目录 ──"
move_and_link \
    "${DATAS_DIR}/output_guoxue" \
    "${TARGET_BASE}/xinghan-guoxue-72b-v1-2-reason/output_guoxue"
move_and_link \
    "${DATAS_DIR}/output_guoxue_v2" \
    "${TARGET_BASE}/xinghan-guoxue-72b-v1-2-reason/output_guoxue_v2"

# ============================================================
# 4. xinghan-ziwei-32b-v1-1
# ============================================================
log ""
log "── ziwei：源文件 ──"
move_and_link \
    "${DATAS_DIR}/xinghan-ziwei-32b-v1-1_260303_260305.jsonl" \
    "${TARGET_BASE}/xinghan-ziwei-32b-v1-1/xinghan-ziwei-32b-v1-1_260303_260305.jsonl"

log ""
log "── ziwei：output 目录 ──"
move_and_link \
    "${DATAS_DIR}/output_ziwei" \
    "${TARGET_BASE}/xinghan-ziwei-32b-v1-1/output_ziwei"

# ============================================================
# 5. tianji-querysafety-4b-v2-3
# ============================================================
log ""
log "── tianji：源文件 ──"
move_and_link \
    "${DATAS_DIR}/tianji-querysafety-4b-v2-3_26030320_26030402_Sheet1.csv" \
    "${TARGET_BASE}/tianji-querysafety-4b-v2-3/tianji-querysafety-4b-v2-3_26030320_26030402_Sheet1.csv"
move_and_link \
    "${DATAS_DIR}/tianji-querysafety-v2-3-system_prompt.txt" \
    "${TARGET_BASE}/tianji-querysafety-4b-v2-3/tianji-querysafety-v2-3-system_prompt.txt"

log ""
log "── tianji：output 目录 ──"
move_and_link \
    "${DATAS_DIR}/output_tianji_querysafety" \
    "${TARGET_BASE}/tianji-querysafety-4b-v2-3/output_tianji_querysafety"

# ============================================================
# 6. xinghan-hepan-72b-v1-2 — 仅 output 目录（源文件已是外部软链）
# ============================================================
log ""
log "── hepan：output 目录 ──"
move_and_link \
    "${DATAS_DIR}/output_henpan_tarot" \
    "${TARGET_BASE}/xinghan-hepan-72b-v1-2/output_henpan_tarot"

# ============================================================
# 7. lingyu-235b-A22b-v9-2
# ============================================================
log ""
log "── lingyu：源文件 ──"
move_and_link \
    "${DATAS_DIR}/lingyu_20260314_0316.jsonl" \
    "${TARGET_BASE}/lingyu-235b-A22b-v9-2/lingyu_20260314_0316.jsonl"

# ============================================================
# 8. 验证
# ============================================================
log ""
log "══ 验证软链接有效性 ══"
ALL_OK=true
for link in \
    "${DATAS_DIR}/xinghan-chart-32b-v1-1-agent_260312_260316.jsonl" \
    "${DATAS_DIR}/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl" \
    "${DATAS_DIR}/output_chart" \
    "${DATAS_DIR}/output_chart_agent" \
    "${DATAS_DIR}/xinghan-guoxue-72b-v1-2-reason_260313_260314.jsonl" \
    "${DATAS_DIR}/output_guoxue" \
    "${DATAS_DIR}/output_guoxue_v2" \
    "${DATAS_DIR}/xinghan-ziwei-32b-v1-1_260303_260305.jsonl" \
    "${DATAS_DIR}/output_ziwei" \
    "${DATAS_DIR}/tianji-querysafety-4b-v2-3_26030320_26030402_Sheet1.csv" \
    "${DATAS_DIR}/output_tianji_querysafety" \
    "${DATAS_DIR}/output_henpan_tarot" \
    "${DATAS_DIR}/lingyu_20260314_0316.jsonl"; do
    if [[ -L "${link}" && -e "${link}" ]]; then
        echo "  ✅ $(basename ${link})"
    else
        echo "  ❌ $(basename ${link})  ← 软链接无效！"
        ALL_OK=false
    fi
done

log ""
if ${ALL_OK}; then
    log "🎉 迁移完成！datas/ 下所有项目均已软链接到 used4evaluation/"
    log ""
    log "used4evaluation/ 结构："
    ls "${TARGET_BASE}/"
else
    log "⚠️  部分项目验证失败，请检查上方错误"
fi
