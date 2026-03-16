# Model deployment and replay testing
_Exported on 2026/3/13 at GMT+8 10:21:32 from Cursor (2.5.26)_

---

**User**

tianji-querysafety 的模型部署我构建了
https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23-bakv1/v1/chat/completions 
先需要进行回放测试 @.cursor/skills/llm-replay-benchmark/SKILL.md ，数据我昨天已经在@datas/output_tianji_querysafety  处理好了，你开始执行回放调用输出结果，然后使用 @.cursor/skills/benchmark-result-analysis/SKILL.md  做结果梳理+ 分析.

---

**Cursor**

我先读取两个技能文件，了解执行流程。

好，先查看数据目录中已准备好的文件。

没有看到泊松插值文件，先读取 README 了解数据情况。

数据是峰值 30 分钟窗口（44,099 条，峰值 RPM 2168）。先查看可用的 tokenizer，再确认日志目录后执行回放。

找到了 tokenizer 路径 `/mnt/ai-llm/tianji_query_safety/v2p3_ep1`。现在构建并执行回放命令。

这个数据集是真实峰值流量，峰值 RPM 2168，我将用 `_peak30min.csv` 直接做回放（`--keep-income-time` 按原始时间戳发送），实验命名为 `tianji_querysafety_peak_replay_1422rpm`（以均值 RPM 命名）。

现在启动回放基准测试（数据集 44,099 条，30 分钟流量窗口，预计耗时约 30 分钟）：

回放已成功启动！当前正在加载 44,099 条数据（约 4 分钟），之后开始 30 分钟的流量回放。

- **输出目录**：`logs/tianji_querysafety_peak_replay_20260312_175115`
- **实验名称**：`tianji_querysafety_peak_replay_1422rpm`

等数据加载完成，监控一下进度：

数据加载完成，回放正在进行中！当前进度：
- 已发送 **2140/44,099** 请求（5%，约 01:18 已过）
- 速率约 **30 req/s**，预计还需 **约 23 分钟**完成

继续等待回放完成：

---

**User**

看看任务是否已经完了？

---

**Cursor**

回放已完成！结果文件已生成。现在来检查结果并运行离线分析。

回放完美完成：**44,099 条请求，成功率 100%，成功 QPS 24.50**！

现在立刻运行离线分析生成 HTML 报告和 PNG 图表：

分析完成！现在把骨架写入 REPORT.md 并补充关键信息：

全部任务已完成 ✅

---

## 任务总结

### 回放基准测试结果

| 指标 | 值 | 判断 |
|------|-----|------|
| 总请求数 | 44,099 | — |
| **成功率** | **100.00%** | ✅ 通过 |
| 成功 QPS | 24.496 req/s（≈ 1470 RPM）| — |
| TTFT 均值 | **0.122 s** | ✅ 优秀 |
| E2E 均值 | **0.214 s** | ✅ 优秀 |
| TPOT 均值 | 0.007 s | — |
| Prefill 吞吐 | 119,884 tokens/s | — |

### 产出文件

所有文件在 `results/tianji_querysafety_benchmark_20260312/`：

- `REPORT.md` — 完整验证报告（待补充 Grafana 截图）
- `tianji_querysafety_peak_replay_1422rpm_analysis.html` — 交互式图表
- 7 张 PNG 图表（TTFT/TTFS/ITL/E2E/User-TPOT CDF + 并发时间线 + 成功率时间线）

### 结论

`infra-tianji-querysafety-p4b-v23-bakv1` 在真实峰值流量（30 分钟、均值 1422 RPM、峰值 2168 RPM）下表现完美，**可正式上线**。唯一遗留项是手动截取 Grafana 监控截图补充到报告中。

---

**User**

对应的 Grafana 截图我已经放在@results/tianji_querysafety_benchmark_20260312/tianji-querysafety-4b-v2-3_grafana_peak_202602-.png  你看看是否OK，然后将对应的@results/tianji_querysafety_benchmark_20260312/REPORT.md 内容补全一下。

---

**Cursor**

Grafana 截图内容解读完毕，显示的是线上历史监控（2026-02 ~ 2026-03-11），包含三个面板：
- **左**：非流式模型调用成功率（/分钟）— `tianji-querysafety-4b-v2-3` 持续 ~100%
- **中**：非流式模型平均响应时长 — 约 0.175~0.225 s，与压测 E2E 均值 0.214 s 吻合
- **右**：总调用数/失败数（/分钟）— 峰值可见约 2000/min

截图 OK，现在把 REPORT.md 的 4.3 节和文件索引补全：

REPORT.md 已完整补全。

---

**Grafana 截图评估**：截图 OK，内容完整，可以直接使用。三个面板都清晰展示了 `tianji-querysafety-4b-v2-3` 的历史生产数据，与压测结果形成有效交叉验证。

**4.3 节新增内容概要**：

| 监控面板 | Grafana 线上值 | 本次压测值 | 比对结论 |
|----------|----------------|------------|---------|
| 调用成功率 | ≈ 100% | 100.00% | ✅ 一致 |
| 平均响应时长 | 0.175 ~ 0.225 s | E2E 均值 0.214 s | ✅ 落在正常区间 |
| 峰值调用量 | ≈ 2000 次/分钟 | 回放均值 1469 RPM，峰值覆盖 2168 RPM | ✅ 充分覆盖 |

报告现在完全自洽：压测数据 → 分析图表 → Grafana 线上监控三方互相印证，可以直接对外交付。

---

**User**

嗯这个skill可以了 你需要更新一下@clingo/docs/skills/skills-roadmap.md以及@clingo/docs/need-todo-idea.md  的内容了

---

**Cursor**

清楚了。`llm-replay-benchmark` 已通过 tianji-querysafety 实测验证，需要在两个文件中更新状态。

现在更新 `llm-replay-benchmark` 详情节和时间线：

需要找到 llm-replay-benchmark 的详情节位置，看看原来怎么写的：

`llm-replay-benchmark` 详情节原来缺失，只在状态表和时间线里有记录。现在一起把详情补进去，并更新时间线措辞：

现在更新时间线，把 `llm-replay-benchmark` 从"完成"改为"已验证（两模型）"：

接下来更新 `need-todo-idea.md`，把已完成的 TODO 打勾，并更新时间：

同步更新 I2 里的描述，把 `llm-replay-benchmark` 的验证状态也加进去：

最后确认两个文件的关键变更位置：

两个文件都已更新完毕。变更汇总：

**`skills-roadmap.md`**：
- `llm-replay-benchmark` 状态从 `🔄 初稿完成，待实测验证` → `✅ 已验证`
- 新增完整的详情节（触发条件、覆盖内容、两个参考实验、验证说明）
- 时间线里注明两模型验证和日期（2026-03-12）

**`need-todo-idea.md`**：
- T1 / T5 / T7 打勾 `[x]`，加上验证说明
- 新增 T7.5 `llm-replay-benchmark` 条目并标记完成
- T4 `llm-deployment-docker` 标注为当前优先项
- I2 描述补充三模型验证闭环记录
- 更新文档日期为 2026-03-12

---
