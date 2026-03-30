#!/usr/bin/env bash
# guofan 项目环境初始化脚本
# 用法：bash setup.sh
#
# 功能：
#   1. 初始化 git submodules（llm-benchmark + data_analysis）
#   2. 安装各 submodule 的 Python 依赖（via uv sync）

set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "  guofan 项目初始化"
echo "  PROJECT_DIR: $PROJECT_DIR"
echo "=================================================="

# ── 检查 uv 是否安装 ──────────────────────────────────
if ! command -v uv &>/dev/null; then
    echo ""
    echo "❌ 未找到 uv，请先安装："
    echo "   curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "   安装后重新运行 bash setup.sh"
    exit 1
fi
echo "✓ uv $(uv --version)"

# ── 初始化 git submodules ──────────────────────────────
# 兼容两种克隆方式：
#   1. git clone --recurse-submodules（submodule 已 checkout，此命令为空操作）
#   2. git clone（未带 --recurse-submodules，此命令完成初始化）
echo ""
echo "==> 初始化 git submodules..."
git -C "$PROJECT_DIR" submodule update --init --recursive
echo "✓ submodules 就绪"

# ── 安装 llm-benchmark 依赖 ────────────────────────────
echo ""
echo "==> 安装 llm-benchmark 依赖（uv sync）..."
if [ -f "$PROJECT_DIR/third_party/llm-benchmark/pyproject.toml" ]; then
    cd "$PROJECT_DIR/third_party/llm-benchmark" && uv sync
    echo "✓ llm-benchmark 依赖安装完成"
else
    echo "⚠️  llm-benchmark 中未找到 pyproject.toml，跳过"
fi

# ── 安装 data_analysis 依赖 ────────────────────────────
echo ""
echo "==> 安装 data_analysis 依赖（uv sync）..."
if [ -f "$PROJECT_DIR/third_party/data_analysis/pyproject.toml" ]; then
    cd "$PROJECT_DIR/third_party/data_analysis" && uv sync
    echo "✓ data_analysis 依赖安装完成"
else
    echo "⚠️  data_analysis 中未找到 pyproject.toml，跳过"
fi

# ── 完成提示 ──────────────────────────────────────────
# ── 关联数据目录 ──────────────────────────────────────

# datas/ 已通过 git 追踪（全是指向 /mnt/ai-infra/datasets/used4evaluation/ 的软链）
# 只需确认挂载点存在即可
if [ ! -d "/mnt/ai-infra/datasets/used4evaluation" ]; then
    echo "⚠️  数据集挂载点不存在：/mnt/ai-infra/datasets/used4evaluation"
    echo "   请确认 /mnt/ai-infra NFS 已挂载，否则 datas/ 下的软链将无法访问"
fi

# logs/ → 共享 benchmark 产物目录
LOGS_TARGET="/mnt/ai-infra/users/shared/benchmark-results/guofan/logs"
if [ -d "$LOGS_TARGET" ]; then
    ln -sfn "$LOGS_TARGET" "$PROJECT_DIR/logs"
    echo "✓ logs/ → $LOGS_TARGET"
elif [ -L "$PROJECT_DIR/logs" ] || [ -d "$PROJECT_DIR/logs" ]; then
    echo "✓ logs/ 已存在，跳过"
else
    mkdir -p "$PROJECT_DIR/logs"
    echo "⚠️  共享 logs 目录不存在（$LOGS_TARGET），已创建本地 logs/"
    echo "   如需访问历史 benchmark 数据，请联系项目负责人获取路径并手动 ln -sfn"
fi

# results/ → 本地目录（可通过 .env.local 覆盖为共享路径）
if [ -f "$PROJECT_DIR/.env.local" ]; then
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env.local"
fi
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_DIR/results}"
if [ "$RESULTS_DIR" != "$PROJECT_DIR/results" ]; then
    mkdir -p "$RESULTS_DIR"
    ln -sfn "$RESULTS_DIR" "$PROJECT_DIR/results"
    echo "✓ results/ → $RESULTS_DIR （来自 .env.local）"
else
    mkdir -p "$PROJECT_DIR/results"
    echo "✓ results/ → 本地目录"
    echo "  （如需指向共享路径，复制 .env.local.example → .env.local 并配置 RESULTS_DIR）"
fi

echo ""
echo "=================================================="
echo "  ✅ 初始化完成！"
echo "=================================================="
echo ""
echo "⚠️  以下内容需要手动处理："
echo "   configs/analysis/*.yaml 中的 dir / output_dir 为个人环境路径，"
echo "   请参考 configs/analysis/template.yaml 新建你自己的配置文件。"
echo ""
