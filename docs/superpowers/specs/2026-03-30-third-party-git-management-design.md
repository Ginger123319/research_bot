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
| `.py` 脚本中的 `sys.path.insert` | 9 个文件 | 使用绝对路径引用 `third_party/` 下的模块 |
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
└── .gitignore            ← 追加：忽略 third_party/speculative-decoding-benchmark/
```

### 2.2 同事上手流程

```bash
git clone --recurse-submodules git@<repo> guofan
cd guofan
bash setup.sh
```

---

## 三、前置条件

执行前需确认：

1. **SSH 访问权限**：对 `git@git.xxwolo.com` 有 SSH 读权限：
   ```bash
   ssh -T git@git.xxwolo.com
   ```
2. **`uv` 已安装**：`setup.sh` 依赖 `uv`：
   ```bash
   uv --version  # 若未安装：curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
3. **`data_analysis` 无未提交变更**：删除目录前须确认：
   ```bash
   git -C third_party/data_analysis status  # 确保 working tree clean
   ```
4. **确认 `data_analysis` 是否已被父仓库 git 追踪**（嵌套 repo 通常不会被追踪，但须验证）：
   ```bash
   git ls-files third_party/data_analysis  # 有输出则说明被追踪，需执行 git rm --cached
   ```

---

## 四、实现步骤

### Step 1：注册 Git Submodule

```bash
# 1. 记录 llm-benchmark 当前工作 commit（软链接指向的实际 repo）
LLM_BENCHMARK_COMMIT=$(git -C "$(readlink -f third_party/llm-benchmark)" rev-parse HEAD)

# 2. 删除软链接（rm 处理软链接，若路径意外变成真实目录则用 rm -rf）
rm third_party/llm-benchmark || rm -rf third_party/llm-benchmark

# 3. 注册 llm-benchmark 为 submodule 并锁定到原 commit
git submodule add git@git.xxwolo.com:ai-infra/llm-benchmark.git third_party/llm-benchmark
git -C third_party/llm-benchmark checkout "$LLM_BENCHMARK_COMMIT"
git add third_party/llm-benchmark

# 4. 记录 data_analysis 当前 commit（防止版本锁定丢失）
DATA_ANALYSIS_COMMIT=$(git -C third_party/data_analysis rev-parse HEAD)

# 5. 从 git 索引中移除 data_analysis（若已被追踪）；若未追踪则此命令会报错但无害
git rm -r --cached third_party/data_analysis 2>/dev/null || true
rm -rf third_party/data_analysis

# 6. 注册 data_analysis 为 submodule
git submodule add git@git.xxwolo.com:ai-infra-any/data_analysis.git third_party/data_analysis

# 7. 将 data_analysis submodule 锁定到原 commit，并更新父仓库 index
git -C third_party/data_analysis checkout "$DATA_ANALYSIS_COMMIT"
git add third_party/data_analysis   # 更新父仓库中 submodule 指向的 commit

# 8. 处理 speculative-decoding-benchmark（若已被追踪则先从索引移除）
git rm -r --cached third_party/speculative-decoding-benchmark/ 2>/dev/null || true
# 防重复追加
grep -qF "third_party/speculative-decoding-benchmark/" .gitignore || \
  echo "third_party/speculative-decoding-benchmark/" >> .gitignore

# 8. 提交 submodule 注册、.gitignore 变更
git add .gitmodules .gitignore third_party/llm-benchmark third_party/data_analysis
git commit -m "chore: register llm-benchmark and data_analysis as git submodules"
```

### Step 2：修复 Shell 脚本硬编码路径

所有脚本均位于 `scripts/` 的二级子目录（距项目根 2 层），替换公式统一为：

```bash
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
```

**批量替换命令（在项目根目录执行）：**

```bash
# 替换 PROJECT_DIR 写死路径
find scripts/ -name "*.sh" | xargs sed -i \
  's|PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"|PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." \&\& pwd)"|g'

# 替换 LLM_BENCHMARK_ROOT 的旧嵌套路径为扁平路径
find scripts/ -name "*.sh" | xargs sed -i \
  's|third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark|third_party/llm-benchmark|g'

# 验证替换结果语法正确（抽查几个典型文件）
bash -n scripts/benchmark/run_phase2_probe.sh
bash -n scripts/benchmark/run_phase1_auto_guoxue4h20.sh

# 提交
git add scripts/
git commit -m "fix: replace hardcoded PROJECT_DIR and LLM_BENCHMARK_ROOT in shell scripts"
```

> **注意**：个别老脚本（如 `run_tianji_querysafety_qps_sweep.sh`）使用 `BENCH_ROOT` 变量直接写死了旧路径，sed 替换后需人工 `grep -r "/mnt/ai-infra" scripts/` 核查确认无遗漏。

### Step 3：修复 Python 脚本硬编码路径

涉及 9 个脚本，全部位于 `scripts/` 二级子目录（`parents[2]` 即项目根）：

| 脚本路径 | 引用的 third_party 模块 |
|---|---|
| `scripts/data/make_peak100_stitched.py` | `data_analysis` |
| `scripts/data/process_guoxue_v2.py` | `data_analysis` |
| `scripts/data/process_guoxue_full.py` | `data_analysis` |
| `scripts/data/process_henpan_tarot_full.py` | `data_analysis` |
| `scripts/data/process_ziwei_full.py` | `data_analysis` |
| `scripts/analysis/offline_analysis.py` | `llm-benchmark/src` |
| `scripts/analysis/compare_analysis.py` | `llm-benchmark/src` |
| `scripts/analysis/check_is_expected.py` | `llm-benchmark/src` |
| `scripts/analysis/analyze_replay_compare.py` | `llm-benchmark/src` |

**替换模式（逐文件手动修改，确保 `_PROJECT` 变量已定义）：**

```python
# 旧（data_analysis 引用）
sys.path.insert(0, "/mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/data_analysis")

# 新
from pathlib import Path
_PROJECT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_PROJECT / "third_party" / "data_analysis"))
```

```python
# 旧（llm-benchmark/src 引用，旧嵌套路径）
sys.path.insert(0, str(_PROJECT / "third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src"))

# 新（扁平路径）
sys.path.insert(0, str(_PROJECT / "third_party/llm-benchmark/src"))
```

```bash
# 提交
git add scripts/
git commit -m "fix: replace hardcoded sys.path in python scripts with relative _PROJECT paths"
```

### Step 4：迁移 YAML 实验配置

> ⚠️ **此步骤必须在原始机器上执行**，前提是 `third_party/speculative-decoding-benchmark/` 目录仍存在于磁盘（即执行 Step 1 之前，或 `speculative-decoding-benchmark/` 目录已单独备份）。新克隆的机器上该目录不存在，Step 4 无需执行（YAML 文件在提交后随 `configs/analysis/` 跟随仓库同步）。

```bash
# 创建目标目录
mkdir -p configs/analysis

# 迁移 3 个文件
cp third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/configs/ziwei_tp8_vs_tp4_20260310.yaml configs/analysis/
cp third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/configs/tianji_4tp_20260311.yaml configs/analysis/
cp third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/configs/template.yaml configs/analysis/
```

迁移后在各实验配置文件（非 template）头部加注释：
```yaml
# ⚠️ 注意：dir / output_dir 为个人环境路径，这是正常现象。
# 克隆后请参考 template.yaml 新建适合你本地环境的配置文件，不要直接修改此文件。
```

```bash
# 提交
git add configs/analysis/
git commit -m "chore: migrate analysis yaml configs from llm-benchmark to configs/analysis/"
```

### Step 5：创建 `setup.sh`

```bash
#!/usr/bin/env bash
# guofan 项目环境初始化脚本
# 用法：bash setup.sh

set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 检查 uv 是否安装
if ! command -v uv &>/dev/null; then
    echo "❌ 未找到 uv，请先安装：curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# 初始化 git submodules
# 兼容两种克隆方式：
#   1. git clone --recurse-submodules（submodule 已 checkout，此命令为空操作）
#   2. git clone（未带 --recurse-submodules，此命令完成初始化）
echo "==> 初始化 git submodules..."
git -C "$PROJECT_DIR" submodule update --init --recursive

echo "==> 安装 llm-benchmark 依赖（uv sync）..."
if [ -f "$PROJECT_DIR/third_party/llm-benchmark/pyproject.toml" ]; then
    cd "$PROJECT_DIR/third_party/llm-benchmark" && uv sync
else
    echo "⚠️  llm-benchmark 中未找到 pyproject.toml，跳过 uv sync"
fi

echo "==> 安装 data_analysis 依赖（uv sync）..."
if [ -f "$PROJECT_DIR/third_party/data_analysis/pyproject.toml" ]; then
    cd "$PROJECT_DIR/third_party/data_analysis" && uv sync
else
    echo "⚠️  data_analysis 中未找到 pyproject.toml，跳过 uv sync"
fi

echo ""
echo "✅ 依赖安装完成！"
echo ""
echo "⚠️  以下内容需要手动处理："
echo "   configs/analysis/*.yaml 中的 dir / output_dir 为个人环境路径，"
echo "   请参考 configs/analysis/template.yaml 新建你自己的配置文件。"
```

```bash
git add setup.sh
git commit -m "feat: add setup.sh for one-command dependency initialization"
```

### Step 6：更新根目录 `README.md`

在根目录 `README.md` 顶部（「项目动机」章节之前）新增「快速开始」章节（将 `git@<实际仓库地址>` 替换为真实 URL）：

```markdown
## 快速开始

### 1. 克隆仓库（含子模块）
\`\`\`bash
git clone --recurse-submodules git@git.xxwolo.com:<group>/guofan.git guofan
cd guofan
\`\`\`

### 2. 初始化依赖
\`\`\`bash
bash setup.sh
\`\`\`

### 3. 配置实验参数（可选）
如需运行 QPS sweep 对比分析，参考 `configs/analysis/template.yaml` 创建你自己的配置文件。
```

```bash
git add README.md
git commit -m "docs: add quick-start section to README with submodule init instructions"
```

---

## 五、不在本次范围内

- `configs/analysis/*.yaml` 内部的 `dir` / `output_dir` 路径**不做自动替换**，属于一次性实验配置，由使用者自行维护（已加注释说明）
- `third_party/speculative-decoding-benchmark/` 内的 `logs/`、`datas/` 等目录**不做处理**，通过 `.gitignore` 忽略整个目录
- `scripts/` 目录之外（如根目录、其他目录）可能存在的硬编码路径**不在本次修复范围**，验证标准中的 `grep` 也仅覆盖 `scripts/`

---

## 六、验证标准

- [ ] `.gitmodules` 文件存在，且包含 `llm-benchmark` 和 `data_analysis` 两条 submodule 记录
- [ ] `git submodule status` 中两个 submodule 均显示正确的 commit hash（无 `+` 前缀表示 dirty）
- [ ] `git clone --recurse-submodules` 后，`third_party/llm-benchmark` 和 `third_party/data_analysis` 均已自动 checkout
- [ ] `bash setup.sh` 执行成功，无报错
- [ ] 任意一个 benchmark 脚本（如 `run_phase2_probe.sh`）在新路径下可正常执行
- [ ] Python 分析脚本（如 `compare_analysis.py`）可正常 `import` 依赖
- [ ] `grep -r "/mnt/ai-infra/users/wnd" scripts/` 无匹配（scripts/ 下硬编码路径已全部清除）
- [ ] `configs/analysis/` 目录存在，包含迁移后的 3 个 YAML 文件
- [ ] `git status` 输出干净，`third_party/speculative-decoding-benchmark/` 不出现在未追踪列表中
