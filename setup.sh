#!/usr/bin/env bash
# guofan 项目环境初始化脚本
# 用法：bash setup.sh
#
# 功能：
#   1. 初始化 git submodules（llm-benchmark + data_analysis）
#   2. 安装各 submodule 的 Python 依赖（via uv sync，失败时 fallback 到 pip --target）
#   3. 确保 .venv 就绪：benchmark wrapper + 分析依赖（plotly / matplotlib 等）

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
    cd "$PROJECT_DIR/third_party/llm-benchmark"
    if uv sync 2>/dev/null; then
        echo "✓ llm-benchmark 依赖安装完成（uv sync）"
    else
        echo "⚠️  uv sync 失败（Python 缓存缺失），跳过；benchmark 将由 wrapper 脚本通过 PYTHONPATH 调用"
    fi
    cd "$PROJECT_DIR"
else
    echo "⚠️  llm-benchmark 中未找到 pyproject.toml，跳过"
fi

# ── 安装 data_analysis 依赖 ────────────────────────────
echo ""
echo "==> 安装 data_analysis 依赖（uv sync）..."
if [ -f "$PROJECT_DIR/third_party/data_analysis/pyproject.toml" ]; then
    cd "$PROJECT_DIR/third_party/data_analysis"
    if uv sync 2>/dev/null; then
        echo "✓ data_analysis 依赖安装完成（uv sync）"
    else
        echo "⚠️  uv sync 失败，跳过"
    fi
    cd "$PROJECT_DIR"
else
    echo "⚠️  data_analysis 中未找到 pyproject.toml，跳过"
fi

# ── 确保 .venv 存在（benchmark + offline_analysis.py 使用）──
echo ""
echo "==> 检查 .venv..."
VENV_BIN="$PROJECT_DIR/.venv/bin"
VENV_PYTHON=""

# 优先用已存在的 .venv，否则用 python3.10 或 python3 创建
if [ -f "$VENV_BIN/python" ]; then
    VENV_PYTHON="$VENV_BIN/python"
    echo "✓ .venv 已存在（$(${VENV_PYTHON} --version 2>&1)）"
else
    for py in python3.10 python3 python; do
        if command -v "$py" &>/dev/null; then
            "$py" -m venv "$PROJECT_DIR/.venv" --without-pip 2>/dev/null \
                || "$py" -m venv "$PROJECT_DIR/.venv"
            VENV_PYTHON="$VENV_BIN/python"
            echo "✓ .venv 已创建（$py）"
            break
        fi
    done
fi

if [ -z "$VENV_PYTHON" ]; then
    echo "⚠️  未找到可用 Python，跳过 .venv 初始化"
else
    VENV_SITE="$PROJECT_DIR/.venv/lib/$(basename $(ls -d $PROJECT_DIR/.venv/lib/python* 2>/dev/null | head -1))/site-packages"

    # ── benchmark wrapper（llm-benchmark 通过 PYTHONPATH 调用）──
    LLM_BENCH_SRC="$PROJECT_DIR/third_party/llm-benchmark/src"
    if [ -f "$VENV_BIN/benchmark" ]; then
        echo "✓ .venv/bin/benchmark 已存在，跳过"
    elif [ -d "$LLM_BENCH_SRC" ]; then
        cat > "$VENV_BIN/benchmark" << WRAPPER
#!/bin/bash
PYTHONPATH="${LLM_BENCH_SRC}:\${PYTHONPATH:-}" \\
  exec "${VENV_BIN}/python" \\
  -m llm_benchmark.benchmark.benchmark "\$@"
WRAPPER
        chmod +x "$VENV_BIN/benchmark"
        echo "✓ .venv/bin/benchmark wrapper 已创建（PYTHONPATH → third_party/llm-benchmark/src）"
    else
        echo "⚠️  third_party/llm-benchmark/src 不存在，benchmark wrapper 未创建"
    fi

    # ── 安装分析依赖（plotly / matplotlib / pandas / numpy）──
    # offline_analysis.py / compare_analysis.py 等需要这些包
    if "$VENV_PYTHON" -c "import plotly, matplotlib" 2>/dev/null; then
        echo "✓ 分析依赖（plotly / matplotlib）已安装，跳过"
    else
        echo "==> 安装分析依赖（plotly / matplotlib）..."
        if [ -n "$VENV_SITE" ] && [ -d "$VENV_SITE" ]; then
            pip install plotly matplotlib --target "$VENV_SITE" -q \
                2>&1 | grep -v "^WARNING:" | grep -v "^$" || true
            echo "✓ 分析依赖安装完成（pip --target $VENV_SITE）"
        else
            echo "⚠️  site-packages 路径未找到，跳过分析依赖安装"
        fi
    fi
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

# ── 后台启动 Dashboard ─────────────────────────────────
SERVE_PORT=18999
SERVE_LOG="$PROJECT_DIR/logs/data-pipeline/serve_${SERVE_PORT}.log"
SERVE_PID_FILE="$PROJECT_DIR/.serve.pid"

# 检查是否已在运行（通过 PID 文件）
if [ -f "$SERVE_PID_FILE" ]; then
    OLD_PID=$(cat "$SERVE_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "ℹ️  Dashboard 已在运行（PID $OLD_PID，端口 $SERVE_PORT）"
        echo "   停止：kill $OLD_PID"
        echo "   日志：tail -f $SERVE_LOG"
        echo ""
        exit 0
    fi
    rm -f "$SERVE_PID_FILE"
fi

# 端口被其他进程占用时，自动替换
if fuser "${SERVE_PORT}/tcp" &>/dev/null; then
    echo "ℹ️  端口 $SERVE_PORT 被占用，正在替换旧进程..."
    fuser -k "${SERVE_PORT}/tcp" 2>/dev/null
    sleep 1
fi

mkdir -p "$(dirname "$SERVE_LOG")"
nohup "$PROJECT_DIR/.venv-serve/bin/python3" "$PROJECT_DIR/scripts/serve.py" \
    "$SERVE_PORT" --bind 0.0.0.0 --directory "$PROJECT_DIR/results" \
    > "$SERVE_LOG" 2>&1 &
SERVE_PID=$!
echo "$SERVE_PID" > "$SERVE_PID_FILE"

sleep 1
if kill -0 "$SERVE_PID" 2>/dev/null; then
    echo "🚀 Dashboard 已后台启动"
    echo "   地址：http://$(hostname -I | awk '{print $1}'):$SERVE_PORT"
    echo "   PID：$SERVE_PID  |  停止：kill $SERVE_PID"
    echo "   日志：tail -f $SERVE_LOG"
else
    echo "⚠️  Dashboard 启动失败，查看日志："
    echo "   tail -20 $SERVE_LOG"
fi
echo ""
