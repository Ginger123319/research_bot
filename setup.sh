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
echo ""
echo "=================================================="
echo "  ✅ 初始化完成！"
echo "=================================================="
echo ""
echo "⚠️  以下内容需要手动处理："
echo "   configs/analysis/*.yaml 中的 dir / output_dir 为个人环境路径，"
echo "   请参考 configs/analysis/template.yaml 新建你自己的配置文件。"
echo ""
