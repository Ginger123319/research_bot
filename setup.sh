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

# ── 安装项目根依赖（serve.py 用：markdown-it-py, pyyaml）──
# 使用独立 .venv-serve，避免与 .venv（可能是共享 SpecForge-venv 软链）冲突
echo ""
echo "==> 安装 serve.py 依赖..."
SERVE_VENV="$PROJECT_DIR/.venv-serve"
if [ ! -d "$SERVE_VENV" ]; then
    uv venv "$SERVE_VENV" --quiet
fi
uv pip install --python "$SERVE_VENV" markdown-it-py pyyaml --quiet
echo "✓ serve.py 依赖安装完成（.venv-serve/）"
echo "  启动 Dashboard：.venv-serve/bin/python3 scripts/serve.py 18999 --directory results"

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

# results/ → 本地工作目录（个人实验结果）
# 共享历史结果通过 SHARED_RESULTS_DIR 让 serve.py 读取，不影响本地 results/
SHARED_RESULTS_TARGET="/mnt/ai-infra/users/shared/benchmark-results/guofan/results"

if [ ! -d "$PROJECT_DIR/results" ] && [ ! -L "$PROJECT_DIR/results" ]; then
    mkdir -p "$PROJECT_DIR/results/models"
    echo "✓ results/ → 本地工作目录（已创建）"
else
    echo "✓ results/ 已存在，跳过"
fi

# 检测共享结果目录：若存在且本地 results/ 不是指向它的软链，
# 则自动配置 SHARED_RESULTS_DIR，让 serve.py Dashboard 展示共享历史
if [ -d "$SHARED_RESULTS_TARGET" ]; then
    LOCAL_REAL=$(realpath "$PROJECT_DIR/results" 2>/dev/null || echo "")
    SHARED_REAL=$(realpath "$SHARED_RESULTS_TARGET" 2>/dev/null || echo "")
    if [ "$LOCAL_REAL" != "$SHARED_REAL" ]; then
        ENV_LOCAL="$PROJECT_DIR/.env.local"
        if ! grep -q "SHARED_RESULTS_DIR" "$ENV_LOCAL" 2>/dev/null; then
            echo "SHARED_RESULTS_DIR=$SHARED_RESULTS_TARGET" >> "$ENV_LOCAL"
            echo "✓ 检测到共享 results → 已写入 .env.local (SHARED_RESULTS_DIR)"
            echo "  serve.py Dashboard 将同时展示共享历史结果和你的本地结果"
        else
            echo "✓ SHARED_RESULTS_DIR 已在 .env.local 中配置"
        fi
    else
        echo "✓ results/ 已指向共享目录，serve.py 直接读取"
    fi
fi

echo ""
echo "=================================================="
echo "  ✅ 初始化完成！"
echo "=================================================="
echo ""
echo "📋 分析配置说明："
echo "   configs/analysis/ 下已有历史实验配置（dir/output_dir 为原机器绝对路径，仅供参考）。"
echo "   新建分析任务时，复制 template.yaml 并使用相对路径（logs/xxx, results/xxx）即可。"
echo "   详细工作流见：configs/analysis/README.md"
echo ""
