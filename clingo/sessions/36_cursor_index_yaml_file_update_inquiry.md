# INDEX.yaml file update inquiry
_Exported on 2026/3/19 at GMT+8 15:13:30 from Cursor (2.5.26)_

---

**User**

刚刚通过对 xinghan-guoxue-72b-v1-2-reason 基于 @.cursor/skills/qps-peak-finder/SKILL.md  的运行后，我看到http://172.21.208.11:18999/  页面上貌似还没有更新最新的结果 ，是不是对应的@results/models/INDEX.yaml 文件也需要做更新呢？ @.cursor/skills/brainstorming/SKILL.md 

---

**Cursor**

我先读取 brainstorming 技能，然后了解当前的文件状态。

现在我来查看 INDEX.yaml 文件以及 qps-peak-finder 的运行结果目录。

让我再看一下 peak finder 的报告和现有的 EVAL_REPORT.md，以全面了解上下文。

好的，我已经完整看完了现状。让我给你一个清晰的分析。

---

## 分析结论

**是的，INDEX.yaml 需要更新。** 同时 README.md 也有一处内容可以完善。

---

### 当前状态对比

| 项目 | 现状（INDEX.yaml）| 应有值（基于 peak-finder 结果）|
|------|-----------------|-------------------------------|
| `sla_max_qps_rps` | `0.245` | `0.2494`（peak-finder 精确值）|
| `sla_max_qps_rpm` | `14.7` | `14.96` |
| `linked_experiments` | 只有 `guoxue_qps_sweep_20260317` + `guoxue_partial_20260317` | **缺少** `results/guoxue_qps_peak_finder_20260318` |
| SLA criterion 备注 | 无交叉验证描述 | 可补充两轮实验交叉验证说明 |

**EVAL_REPORT.md 已经是最新的**（已包含双实验对比内容），只有 INDEX.yaml 和 README.md 没跟上。

---

**为什么页面没更新？**  
`http://172.21.208.11:18999/` 的 dashboard 读取 `results/models/INDEX.yaml` 作为入口。INDEX.yaml 里的 `linked_experiments` 缺少最新实验目录，所以 peak-finder 的图表（`plot_*.html`）和 REPORT.md 不会出现在页面上。

---

现在我来执行更新：

清楚了，现在直接更新 INDEX.yaml 中 guoxue 模型的条目：

更新完成。再顺手把 `results/README.md` 中 guoxue_qps_peak_finder 的条目状态也从"进行中"确认一下是否已经是完成态：

README.md 已经是正确状态，没有问题。

---

## 已完成的更新汇总

`results/models/INDEX.yaml` 中 `xinghan-guoxue-72b-v1-2-reason` 条目做了 4 处更新：

| 字段 | 旧值 | 新值 |
|------|------|------|
| `eval_completed_date` | `2026-03-17` | `2026-03-18` |
| `sla_max_qps_rps` | `0.245` | `0.2494`（加注释说明交叉验证一致） |
| `sla_max_qps_rpm` | `14.7` | `14.96` |
| `linked_experiments` | 只有 sweep + partial 两个 | **新增** `guoxue_qps_peak_finder_20260318` 排首位，另两个保留注释说明角色 |
| `recommendation` | 提及 0.245 req/s | 更新为 0.2494 + 明确"两轮交叉验证" + 补充 1.39× buffer 计算 |

**`results/README.md`** 无需改动，已正确记录 peak-finder 结果。

这样页面 `http://172.21.208.11:18999/` 在下次刷新时应该能读到 `guoxue_qps_peak_finder_20260318` 目录下的三张交互式图表（`plot_qps.html`、`plot_throughput.html`、`plot_latency_2d.html`）和 REPORT.md 了。

---

**User**

另外我希望页面展示内容也可以将 极限RPS 下的情况（可容并发，P90 e2e ,P90 TTFS ）也展示一下，意思就给出服务在最大吞吐场景下 还是有提供服务的能力，所以目前这些内容可以辅助在设置服务承载能力上作为参考以及启动配置提供.

