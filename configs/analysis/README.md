# configs/analysis — 分析配置说明

本目录存放 QPS benchmark 分析任务的 YAML 配置文件，每个文件对应一次具体的实验分析。

---

## 工作流概览

```
1. 跑 benchmark（scripts/benchmark/run_*.sh）
        ↓ 输出 CSV 文件
2. logs/<exp_dir>/        ← benchmark 原始结果（共享 NFS，只读）
        ↓ 写分析配置
3. configs/analysis/<model>_<deploy>_<date>.yaml   ← 你要创建的文件
        ↓ 执行分析
4. results/<model>_<deploy>_<date>/   ← 生成 HTML 图表 + REPORT.md
```

---

## 快速上手：创建你的第一个分析配置

**第一步：找到实验日志目录**

```bash
ls logs/
# 示例输出：
# tianji_qps_20260311_200338/
# ziwei_8tp_qps_20260310_all/
```

**第二步：复制模板，新建配置文件**

```bash
cp configs/analysis/template.yaml configs/analysis/mymodel_tp8_20260401.yaml
```

命名规范：`<model>_<deploy>_<date>.yaml`

**第三步：编辑配置文件**

```yaml
groups:
  - label: "mymodel TP8"
    dir: "logs/mymodel_8tp_qps_20260401_120000"   # benchmark 日志目录

x_key: request_rate

output_dir: "results/mymodel_tp8_20260401"        # 分析结果输出目录
```

**第四步：执行分析**

```bash
# 从项目根目录运行
source third_party/llm-benchmark/.venv/bin/activate
python3 -m llm_benchmark.analysis.analysis.multi_exp_compare \
    --config configs/analysis/mymodel_tp8_20260401.yaml
```

执行完毕后，`results/mymodel_tp8_20260401/` 目录下会生成：
- `plot_qps.html` — QPS vs 吞吐量曲线（交互式）
- `plot_latency_2d.html` — 延迟分布曲线
- `plot_throughput.html` — 吞吐量曲线
- `REPORT.md` — 文字报告（SLA 判断 + 拐点结论）

---

## 路径说明

| 字段 | 说明 | 推荐写法 |
|------|------|----------|
| `dir` | benchmark 脚本输出的日志目录 | `logs/exp_dir_name`（相对路径） |
| `output_dir` | 分析结果输出目录 | `results/model_deploy_date`（相对路径） |

> 路径均**相对于项目根目录**（即执行 `python3 -m ...` 命令时所在的目录）。  
> 已有的示例配置（如 `tianji_4tp_20260311.yaml`）使用了绝对路径，这是历史遗留，  
> 新建配置请统一使用相对路径，克隆到任意机器均可直接运行。

---

## SLA 配置

不填 `sla` 块则使用通用默认值：

| 指标 | 默认值 | 含义 |
|------|--------|------|
| `ttfs_p90` | 1.5s | 首 Token 延迟 P90 |
| `e2e_p90` | 150s | 完整响应 P90 |
| `success_rate` | 99% | 请求成功率 |

**常见调整场景：**

```yaml
# 短输出模型（如安全检测，输出 < 100 token）
sla:
  ttfs_p90: 1.5
  e2e_p90: 0.4        # 400ms，取代通用 150s
  success_rate: 0.99

# 长文本生成模型（如 reasoning / 长报告）
sla:
  ttfs_p90: 2.0
  e2e_p90: 300.0
  success_rate: 0.99
```

---

## 已有配置说明

| 文件 | 模型 | 实验内容 |
|------|------|----------|
| `tianji_4tp_20260311.yaml` | tianji-querysafety-4b-v2-3 | 4TP 单实例 QPS 拐点扫描，e2e_p90 收紧至 400ms |
| `ziwei_tp8_vs_tp4_20260310.yaml` | ziwei-32b | TP8 vs TP4 容量对比 |
| `template.yaml` | — | 模板文件，复制后填写使用 |

> ⚠️ 已有配置中的 `dir` / `output_dir` 是原始机器的绝对路径，**不要直接运行**。  
> 它们作为参考示例保留，展示实验背景和 SLA 参数选择依据。
