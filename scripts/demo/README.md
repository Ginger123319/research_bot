# Demo：从 Grafana（VictoriaMetrics）查询线上模型承载量

本目录包含一个独立的演示脚本，展示如何通过 VictoriaMetrics API 查询已上线模型的实际流量峰值，并与评测结论做自动对比。

---

## 背景

我们的模型评测流程会给出 **单实例 SLA RPM**（如 tianji-querysafety 单实例 480 RPM）。  
模型上线后，Grafana 监控平台（数据源是 VictoriaMetrics）会持续采集 SGLang 的请求指标。  
这个脚本让你可以：

1. **直接用部署名查流量**，无需打开 Grafana 手动找面板
2. **自动换算总容量**（单实例 SLA × 实例数）并输出使用率
3. **支持 JSON 输出**，方便集成到日报脚本或 CI 流程

---

## 前置条件

- 能访问公司内网（脚本直接连 `172.21.52.62:8481`）
- Python 3.8+，**不需要安装任何额外依赖**（只用标准库）

---

## 快速上手

```bash
# 进入项目根目录
cd /mnt/ai-infra/users/wnd/workspace/execute/guofan

# 最简单的用法：只传部署名
python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4
```

输出示例：

```
────────────────────────────────────────────────────────
  在线承载量报告 — tianji-querysafety-p4b-v23-tp4
────────────────────────────────────────────────────────
  指标格式   : sglang:num_requests_total
  当前实时   : 1048 RPM
  7日峰值    : 3524 RPM

  日期           峰值 RPM
  ────────────────────────
  2026-03-20     3433   ████████████████████
  2026-03-19     3524   ████████████████████
  2026-03-14      701   ████
  2026-03-13      374   ██
────────────────────────────────────────────────────────
```

---

## 带 SLA 对比（推荐）

加上 `--instances`（当前部署实例数）和 `--sla-rpm`（单实例评测 SLA），会自动计算**总容量使用率**：

```bash
# tianji-querysafety：8 实例，单实例 SLA = 480 RPM，总容量 = 3840 RPM
python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4 \
  --instances 8 --sla-rpm 480

# lingyu：10 实例，单实例 SLA = 180 RPM，总容量 = 1800 RPM
python3 scripts/demo/query_online_rpm.py lingyu-p235b-a22b-v9-final \
  --instances 10 --sla-rpm 180
```

输出中会多出：

```
  评测 SLA   : 480 RPM × 8 实例 = 3840 RPM
  容量使用率 : 92.0%  ⚡ 接近上限
```

颜色说明：
- 🟢 绿色（< 80%）：容量充足
- 🟡 黄色（80%～100%）：接近上限，需关注
- 🔴 红色（> 100%）：已超出总容量，需紧急扩容

---

## 所有参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `deployment` | 部署名（K8s LWS 名称） | 必填 |
| `--days N` | 查询最近 N 天 | 7 |
| `--instances N` | 当前部署实例数 | 1 |
| `--sla-rpm N` | 单实例评测 SLA RPM | 0（不对比）|
| `--json` | 输出原始 JSON | 否 |

---

## 如何找到"部署名"？

部署名 = Kubernetes LWS（LeaderWorkerSet）的名称，对应 VictoriaMetrics 中的  
`nexus_aiinfra_cece_com_name` 标签。

**常见部署名参考：**

| 模型 | 部署名 | 实例数 | 单实例 SLA |
|------|--------|--------|-----------|
| tianji-querysafety-4b-v2-3 | `tianji-querysafety-p4b-v23-tp4` | 8 | 480 RPM |
| lingyu-235b-A22b-v9-2 | `lingyu-p235b-a22b-v9-final` | 10 | 180 RPM |

如果不确定部署名，可以执行下面这条命令列出所有在线部署：

```bash
curl -s 'http://172.21.52.62:8481/select/0/prometheus/api/v1/label/nexus_aiinfra_cece_com_name/values' \
  | python3 -c "import json,sys; [print(' ', v) for v in json.load(sys.stdin)['data']]"
```

---

## JSON 输出（集成到日报脚本）

加 `--json` 参数输出结构化数据，方便写进日报 Markdown：

```bash
python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4 --json
```

```json
{
  "current_rpm": 1048.0,
  "daily_max_7d": 3524.0,
  "daily": [
    {"date": "2026-03-13", "max_rpm": 374.0},
    {"date": "2026-03-14", "max_rpm": 701.0},
    {"date": "2026-03-19", "max_rpm": 3524.0},
    {"date": "2026-03-20", "max_rpm": 3433.0}
  ],
  "metric_used": "sglang:num_requests_total"
}
```

---

## Dashboard 集成（serve.py）

如果你在用 `serve.py` 启动的评估平台，在线承载量已自动集成在模型卡片中：

```bash
.venv/bin/python scripts/serve.py 18999 --bind 0.0.0.0 --directory results
```

打开 `http://<服务器IP>:18999/` 即可看到每个模型卡片底部的"📊 在线承载量"区块。

要为新上线模型接入，只需在 `results/models/INDEX.yaml` 对应模型条目下加两行：

```yaml
online_deployment_name: <部署名>        # 对应 K8s LWS 名称
deployment:
  current_instances: <实例数>
```

---

## 底层原理（给好奇的同学）

脚本通过 VictoriaMetrics PromQL API 计算 RPM：

**当前 RPM（1分钟滑窗）：**
```
sum(rate(sglang:num_requests_total{nexus_aiinfra_cece_com_name="<部署名>"}[1m])) * 60
```

**单日最大 RPM（24小时内每分钟统计的最大值）：**
```
max_over_time(
  sum(rate(sglang:num_requests_total{...}[1m]))[24h:1m]
) * 60
```

两种 SGLang 版本的指标名都会自动尝试：
- 新版（0.4+）：`sglang_num_requests_total`（下划线）
- 旧版：`sglang:num_requests_total`（冒号，recording rule 格式）
