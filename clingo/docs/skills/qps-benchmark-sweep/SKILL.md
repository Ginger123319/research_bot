---
name: qps-benchmark-sweep
description: Use when finding a deployed LLM service's QPS capacity limit or inflection point — designing sweep levels, configuring the benchmark wrapper, running comparison experiments (TP vs DP), and tracking multi-hour sweep progress. For visualizing and analyzing sweep results across multiple groups, use qps-sweep-comparison skill instead.
---

# QPS Benchmark Sweep

## Overview

通过多档 QPS 逐步施压，找到服务的**拐点**（成功率开始下降或延迟明显抬升的临界 QPS）。

所有 QPS 扫描脚本统一调用 `example_llm_benchmark_test.sh` 包装脚本，通过环境变量传参，`CONFIG_LIST="qps,0,0,0"` 表示 vanilla（无投机解码）配置。

---

## 快速参数速查

| 参数 | 典型值 | 说明 |
|------|--------|------|
| `CONFIG_LIST` | `"7.00,0,0,0"` | `qps,steps,topk,draft`，vanilla 后三位全 0 |
| `NUM_PROMPTS` | `qps × duration_secs` | 确保 ≤ 数据集行数 |
| 每档时长 | 2700s（45min）| 均匀扫描；拐点精查用 3600s |
| `COOLDOWN_SECS` | 60~90s | 档位间冷却，让服务恢复稳定 |
| `--max-completion-tokens` | 4096（对话）/ 256（安全拦截等短输出）| 按模型输出长度设置 |
| `--no-kvcache` / `no_kvcache=True` | 压测默认开启 | 每请求加随机 UUID 前缀，防命中 KV 缓存 |

---

## 档位设计策略

### 策略 A：均匀扫描（适合首次探索，未知拐点位置）

```
QPS 7.00 → 4.00，30 档，步进 ~0.103，每档 45min
```

适用：没有历史数据的新模型，想覆盖宽范围找大致拐点。

### 策略 B：密度加权（适合精查已知拐点区域）

```
边界区 (0.02步, 60min/档)：1.00 → 0.86  共 8 档  ← 拐点附近精细扫
中间区 (0.04步, 45min/档)：0.78 → 0.60  共 6 档
低 QPS  (0.05步, 30min/档)：0.55 → 0.46  共 2 档
```

适用：已从策略 A 大致确定拐点，需要精确定位。

---

## 核心调用模式

**服务 URL 说明**：URL 由平台手动部署后提供，脚本永远使用 `--skip-launch-server`，不自行启动 server（`example_llm_benchmark_test.sh` 有服务启动能力，但当前场景不用）。

```bash
LEVEL_DIR="${OUTPUT_DIR}/qps_${qps}"
mkdir -p "${LEVEL_DIR}"

NUM_PROMPTS="${NUM_PROMPTS}" \
TARGET_MODEL="${TARGET_MODEL}" \
TOKENIZER="${TOKENIZER}" \
CONFIG_LIST="${qps},0,0,0" \
DATASET_PATH="${DATASET_PATH}" \
OUTPUT_DIR="${LEVEL_DIR}" \
bash "${BENCHMARK_SCRIPT}" \
    --skip-launch-server \
    --server-url "${SERVER_URL}" \
    --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
    || {
        echo "⚠️ 档位 QPS=${qps} 异常，记录后继续"
        echo "failed_qps=${qps}" >> "${PROGRESS_FILE}"
    }
```

`BENCHMARK_SCRIPT` 路径：`${BENCH_ROOT}/modao/src/scripts/example_llm_benchmark_test.sh`

`BENCH_ROOT`：`/mnt/ai-infra/users/wnd/workspace/execute/speculative-decoding-benchmark`

---

## 每档输出结构 & 执行中监控

每个档位执行完后，在 `${OUTPUT_DIR}/qps_${X}/` 下生成 4 个文件：

```
qps_0.88/
  dataset.csv                       ← 本档使用的数据子集
  llm_benchmark_vanilla_qps0.88.log ← 执行过程 + 汇总统计
  vanilla_qps0.88.argv.csv          ← 完整参数记录
  vanilla_qps0.88.csv               ← 每条请求的详细结果
```

**执行中健康检查**（扫描运行时随时可做）：

```bash
# 1. 查看当前在跑哪个档位
cat logs/<exp>/progress.txt

# 2. 看当前档位是否正常发送请求（进度条在走）
tail -f logs/<exp>.log

# 3. 进入当前档位目录，看详细执行日志
cat logs/<exp>/qps_<X>/llm_benchmark_vanilla_qps<X>.log
```

**从 `llm_benchmark_vanilla_qps{X}.log` 判断档位是否健康**：

```
请求完成统计:
总发送数: 3168        ← 应 ≈ NUM_PROMPTS
成功: 3167
成功率: 99.97%        ← ≥ 99% = 正常；< 99% = 接近或超过拐点
POST异常: 0           ← 非 0 说明网络或服务异常
POST非200: 1          ← 偶发 1~2 可接受
流解析异常: 0
成功QPS: 0.88 请求/秒  ← 应与设定 QPS 吻合
```

---

## 进度追踪

```bash
PROGRESS_FILE="${OUTPUT_DIR}/progress.txt"

# 循环内写入
{
    echo "current_level=${CURRENT}"
    echo "current_qps=${qps}"
    echo "current_start=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "elapsed_h=$(echo "scale=1; ($(date +%s) - ${START_TIME})/3600" | bc)"
} >> "${PROGRESS_FILE}"

# 查看进度
cat logs/<exp>/progress.txt
tail -f logs/<exp>.log
```

---

## 对照实验设计（TP vs DP）

同一个模型在不同部署配置下跑两组扫描，比较吞吐/延迟曲线。

**QPS 等比放大原则**：DP 副本数 = N 时，对照扫描的 QPS 范围应 ×N：

```
4TP × 1实例：QPS 7.0 → 4.0
1TP × 4DP：  QPS 28.0 → 16.0   （= 4×，理论吞吐等比）
```

两组扫描应使用**相同数据集、相同每档时长**，结果通过 analysis 工具加载后可做曲线对比。

---

## 执行命令

```bash
# 后台长时间运行（推荐）
# ⚠️ nohup 重定向路径统一写入 logs/data-pipeline/，区别于 benchmark 工具自身产物
nohup bash scripts/benchmark/run_<model>_qps_sweep.sh \
    > logs/data-pipeline/<model>_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# 查看进度
cat logs/<exp_dir>/progress.txt
tail -f logs/data-pipeline/<model>_qps_<timestamp>.log

# 分析结果（sweep 完成后）→ 见 qps-sweep-comparison Skill
analysis --host 0.0.0.0 --port 8050 --exp logs/<exp_dir>
```

---

## 多段扫描合并流程

**触发条件**：QPS 范围太宽，分多次运行（如先跑 [4.0, 7.0]，再跑 [7.0, 10.0]）。

**操作步骤**：

```bash
# 1. 新建合并目录
mkdir -p logs/<model>_<config>_all/

# 2. 将各段运行的档位子目录复制进去
cp -r logs/<exp_run1>/qps_*  logs/<model>_<config>_all/
cp -r logs/<exp_run2>/qps_*  logs/<model>_<config>_all/

# 3. 若有异常档位（如 KV Cache 热身异常），创建 _filtered 版本
mkdir -p logs/<model>_<config>_all_filtered/
# 复制时跳过异常档位（如 qps_6.90、qps_7.00）
for d in logs/<model>_<config>_all/qps_*; do
    qps=$(basename $d | sed 's/qps_//')
    if [[ "$qps" != "6.90" && "$qps" != "7.00" ]]; then
        cp -r "$d" logs/<model>_<config>_all_filtered/
    fi
done

# 4. 对合并目录运行分析（→ 见 qps-sweep-comparison Skill）
analysis --host 0.0.0.0 --port 8050 --exp logs/<model>_<config>_all_filtered/
```

**命名约定**：
- 合并目录：`logs/<model>_<config>_all/`（不含时间戳，因为跨多次运行）
- 剔除异常后：`logs/<model>_<config>_all_filtered/`

**已有案例**：
- `logs/ziwei_4tp_qps_20260310_all/`、`logs/ziwei_8tp_qps_20260310_all/`（ziwei TP4 vs TP8 合并）
- `logs/tianji_4tp_qps_merged/`、`logs/tianji_4tp_qps_merged_filtered/`（tianji 低段+高段合并，剔除 KV Cache 异常）

---

## 数据集要求

- CSV 必须包含 `income_time`、`messages`、`prompt`（空列也必须存在，否则 `KeyError: 'prompt'`）
- `NUM_PROMPTS = ceil(qps × duration_secs)`，必须 ≤ 数据集实际行数（不含表头）
- 推荐使用**峰值窗口采样文件**（`_peak{N}min.csv`），避免全量 CSV 体积过大

---

## 拐点判断指标

| 指标 | 正常 | 拐点信号 |
|------|------|---------|
| 请求成功率 | ≥ 99% | < 99% |
| TTFT P90 | 基线 × 1.5 以内 | 明显抬升或跳变 |
| 吞吐（output tokens/s）| 随 QPS 线性增长 | 增长停滞或下降 |

---

## 常见错误

| 错误 | 根因 | 修复 |
|------|------|------|
| `KeyError: 'prompt'` | CSV 缺少 `prompt` 列 | 输出列补空 `prompt`：`df["prompt"] = ""` |
| NUM_PROMPTS 超过数据集行数 | 高 QPS × 长时长 = 大需求量 | 增大数据集 或 缩短单档时长 |
| 档位结果目录为空 | `bash` 里 `set -e` 导致单档失败终止整个扫描 | 关键调用加 `|| { echo ...; }` 捕获异常继续 |
| 对照实验 QPS 未等比放大 | DP 扩容但 QPS 范围未同步 | 副本数 N → QPS ×N |
| COOLDOWN 不足导致服务未恢复 | 高 QPS 档结束后服务队列未排空 | 对话类模型建议 ≥90s，安全拦截类 ≥60s |

---

**参考脚本**：`scripts/benchmark/run_tianji_querysafety_qps_sweep.sh`、`run_tianji_querysafety_opti_qps_sweep.sh`、`run_ziwei_4tp_qps_benchmark.sh`
