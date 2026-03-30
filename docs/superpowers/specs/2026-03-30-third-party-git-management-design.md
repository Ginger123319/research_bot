# 设计文档：third_party 依赖 Git 管理与项目可移植化

**日期**：2026-03-30  
**状态**：待实现  
**背景**：使同事能够通过 `git clone --recurse-submodules` 后执行 `bash setup.sh` 完成全部依赖初始化，消除个人路径硬编码，确保项目在任意机器上可直接运行。

---

## 一、现状问题

### 1.1 依赖管理现状

| 目录 | 当前状态 | 问题 |
|---|---|---|
| `third_party/llm-benchmark` | 软链接 → `/mnt/ai-infra/users/wnd/workspace/execute/llm-benchmark` | 非 git 追踪，同事不知道要 clone 什么、link 到哪里 |
| `third_party/data_analysis` | 独立 git repo（有 remote） | 未注册为 submodule，不在 `.gitmodules` 里 |
| `third_party/speculative-decoding-benchmark` | 裸目录（无 git） | 本身已无用，仅作为 `llm-benchmark` 的嵌套容器 |

### 1.2 硬编码路径现状

| 类型 | 数量 | 问题 |
|---|---|---|
| `.sh` 脚本中的 `PROJECT_DIR` | 24 个文件 | `PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"` 写死 |
| `.py` 脚本中的 `sys.path.insert` | 5 个文件 | 使用绝对路径引用 `third_party/` 下的模块 |
| YAML 实验配置中的 `dir` / `output_dir` | 3 个文件（存于 llm-benchmark 内） | 写死个人绝对路径，且文件位置不对（混入了工具 repo） |

---

## 二、目标状态

### 2.1 仓库结构

```
guofan/
├── third_party/
│   ├── llm-benchmark/    ← git submodule → git@git.xxwolo.com:ai-infra/llm-benchmark.git
│   └── data_analysis/    ← git submodule → git@git.xxwolo.com:ai-infra-any/data_analysis.git
├── configs/
│   └── analysis/         ← 迁入 3 个 YAML 实验配置（原存于 llm-benchmark/configs/）
├── setup.sh              ← 新增：一键环境初始化入口
└── .gitignore            ← 新增：忽略 third_party/speculative-decoding-benchmark/
```

### 2.2 同事上手流程

```bash
git clone --recurse-submodules git@<repo> guofan
cd guofan
bash setup.sh
```

---

## 三、实现步骤

### Step 1：注册 Git Submodule

1. 删除软链接 `third_party/llm-benchmark`
2. 执行：
   ```bash
   git submodule add git@git.xxwolo.com:ai-infra/llm-benchmark.git third_party/llm-benchmark
   ```
3. 记录 `third_party/data_analysis` 当前 commit，删除目录，执行：
   ```bash
   git submodule add git@git.xxwolo.com:ai-infra-any/data_analysis.git third_party/data_analysis
   git -C third_party/data_analysis checkout <recorded-commit>
   ```
4. 在 `.gitignore` 中追加：
   ```
   third_party/speculative-decoding-benchmark/
   ```

### Step 2：修复 Shell 脚本硬编码路径

将所有 `scripts/benchmark/*.sh` 中的：
```bash
PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
```
替换为：
```bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
```

涉及文件：24 个（含少数在 `scripts/` 其他子目录下的脚本，深度不同时路径层数相应调整）。

同时将 `LLM_BENCHMARK_ROOT` 的引用从：
```bash
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark"
```
改为：
```bash
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
```

### Step 3：修复 Python 脚本硬编码路径

将涉及的 5 个 `.py` 脚本中的绝对路径 `sys.path.insert`，替换为基于 `__file__` 的相对推导：

```python
# 旧
sys.path.insert(0, "/mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/data_analysis")

# 新
from pathlib import Path
_PROJECT = Path(__file__).resolve().parents[N]  # N 根据脚本所在深度确定
sys.path.insert(0, str(_PROJECT / "third_party" / "data_analysis"))
```

对于引用 `llm-benchmark/src` 的脚本，路径同步由旧嵌套路径改为扁平路径：
```python
# 旧
str(_PROJECT / "third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src")

# 新
str(_PROJECT / "third_party/llm-benchmark/src")
```

### Step 4：迁移 YAML 实验配置

将以下 3 个文件从 `third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/configs/` 迁移至 `configs/analysis/`：

- `ziwei_tp8_vs_tp4_20260310.yaml`
- `tianji_4tp_20260311.yaml`
- `template.yaml`（保留为模板）

迁移后在文件头加注释：
```yaml
# ⚠️ 注意：dir / output_dir 为个人环境路径，克隆后需根据本地 PROJECT_DIR 手动更新。
# 参考 template.yaml 新建你自己的配置文件。
```

### Step 5：创建 `setup.sh`

```bash
#!/usr/bin/env bash
# guofan 项目环境初始化脚本
# 用法：bash setup.sh

set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 初始化 git submodules..."
git -C "$PROJECT_DIR" submodule update --init --recursive

echo "==> 安装 llm-benchmark 依赖（uv sync）..."
cd "$PROJECT_DIR/third_party/llm-benchmark" && uv sync

echo "==> 安装 data_analysis 依赖（uv sync）..."
cd "$PROJECT_DIR/third_party/data_analysis" && uv sync

echo ""
echo "✅ 依赖安装完成！"
echo ""
echo "⚠️  以下内容需要手动处理："
echo "   configs/analysis/*.yaml 中的 dir / output_dir 为个人环境路径，"
echo "   请参考 configs/analysis/template.yaml 新建你自己的配置文件。"
```

### Step 6：更新 README

在 README 顶部或专门的「快速开始」章节中，补充初始化说明：

```markdown
## 快速开始

### 1. 克隆仓库（含子模块）
\`\`\`bash
git clone --recurse-submodules git@<repo> guofan
cd guofan
\`\`\`

### 2. 初始化依赖
\`\`\`bash
bash setup.sh
\`\`\`

### 3. 配置实验参数（可选）
如需运行 QPS sweep 对比分析，参考 `configs/analysis/template.yaml` 创建你自己的配置文件。
```

---

## 四、不在本次范围内

- `configs/analysis/*.yaml` 内部路径**不做自动替换**，保留个人路径并加注释说明（这类一次性实验配置由使用者自行维护）
- `third_party/speculative-decoding-benchmark/` 内的 `logs/`、`datas/` 等目录**不做处理**，通过 `.gitignore` 忽略整个目录

---

## 五、验证标准

- [ ] `git clone --recurse-submodules` 后，`third_party/llm-benchmark` 和 `third_party/data_analysis` 均已自动 checkout
- [ ] `bash setup.sh` 执行成功，无报错
- [ ] 任意一个 benchmark 脚本（如 `run_phase2_probe.sh`）在新路径下可正常执行
- [ ] Python 分析脚本（如 `compare_analysis.py`）可正常 `import` 依赖
