#!/bin/bash
# ============================================================
# chart-32b output 目录补迁脚本
# （主迁移脚本已完成其余所有内容，本脚本仅处理 output_chart 和
#   output_chart_agent，在 chart-32b benchmark 全部完成后执行）
#
# 用法：
#   bash scripts/migrate_chart_outputs.sh
# ============================================================

set -euo pipefail

TARGET_BASE="/mnt/ai-infra/datasets/used4evaluation"
DATAS_DIR="${PROJECT_DIR}/datas"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

move_and_link() {
    local src="$1"
    local dst="$2"
    if [[ ! -e "${src}" && ! -L "${src}" ]]; then
        log "  ⚠️  跳过（不存在）: $(basename ${src})"; return
    fi
    if [[ -L "${src}" ]]; then
        log "  ⚠️  已是软链接，跳过: $(basename ${src})"; return
    fi
    log "  mv  $(basename ${src})"
    mv "${src}" "${dst}"
    ln -s "${dst}" "${src}"
    log "  ✅  $(basename ${src}) → ${dst}"
}

log "── chart-32b output 目录补迁 ──"
move_and_link "${DATAS_DIR}/output_chart"       "${TARGET_BASE}/xinghan-chart-32b-v1-1-agent/output_chart"
move_and_link "${DATAS_DIR}/output_chart_agent" "${TARGET_BASE}/xinghan-chart-32b-v1-1-agent/output_chart_agent"

log ""
for link in "${DATAS_DIR}/output_chart" "${DATAS_DIR}/output_chart_agent"; do
    [[ -L "${link}" && -e "${link}" ]] && echo "  ✅ $(basename ${link})" || echo "  ❌ $(basename ${link})"
done

log "🎉 chart output 目录迁移完成"
