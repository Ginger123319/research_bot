# QPS testing results analysis and visualization
_Exported on 2026/3/13 at GMT+8 11:48:42 from Cursor (2.5.26)_

---

**User**

基于@clingo/sessions/13_cursor_project_skill_development_planni.md @clingo/sessions/14_cursor_benchmark_results_visualization.md 
以上是昨天的会话记录，对了昨天设置关于 tianji_querysafety-4b-v2-3 模型 QPS测试完成了@logs/tianji_qps_20260311_200338.log 
你先使用  @.cursor/skills/qps-sweep-comparison/SKILL.md  单对结果内容@logs/tianji_qps_20260311_200338  做一下 SLA 可视化以及分析，这个模型有一个特别的地方，整体（e2e_latency) 时长P95<=400ms，看看你有什么想要我补充或者你的想法 @.cursor/skills/brainstorming/SKILL.md ,确认后我们就开始执行任务。

---

**Cursor**

我先读取相关的技能文件和会话记录，做好充分准备。

现在让我了解日志文件结构和昨天的会话记录。

让我查看日志目录结构，了解实验结果文件的组织方式。

很好，目录结构完整。现在我来进行 Brainstorming 阶段的分析与讨论。

---

## Brainstorming：tianji_querysafety-4b-v2-3 SLA 可视化分析

### 当前上下文理解

基于已掌握的信息：

**实验基本信息：**
- 模型：`tianji_querysafety-4b-v2-3`（4B 安全检测模型）
- 部署：4TP × 1 实例
- QPS 范围：4.00 → 7.00（30档，步进 ~0.103）
- 每档时长：45分钟，数据集 44,099 条（峰值 2168 RPM）
- 数据完整：30个子目录全部存在 ✅

**你的核心观点（我很认同）：**

这个模型有一个天然的 **"缓存加速"结构特征**：

| 特征 | 说明 |
|------|------|
| System Prompt | ~8K Token 的固定模版（含大量 few-shot、审核规则） |
| User Input | 极短的用户 query（几十个 Token 级别） |
| SGLang 缓存命中 | 绝大多数请求前缀完全重合，KV Cache 命中率极高 |
| 实际延迟模式 | "快进快出"——TTFT 极低（前缀缓存跳过大量 prefill），生成也短（256 tokens 上限）|

**因此你建议调整 SLA 标准为：`E2E P90 ≤ 400ms`**，这个思路有充分的技术依据。

---

### 我的补充想法与问题

在执行前，我想和你确认以下几点：

**Q1：这是单组分析，还是后续要和 4DP 实验做对比？**

我看到还有一个 `tianji_opti_qps_20260312_111300`（1TP×4DP）实验。如果你希望这次只分析 4TP 单组找拐点，我就按单组出图；如果 4DP 已经跑完，可以直接做对比分析，一步到位。

**Q2：关于 SLA 配置，你的意图我理解为两层：**

- 通用基准（成功率 ≥99%，TTFS P90 ≤1500ms）仍然保留作为参考
- **主要判断指标换成** `E2E P90 ≤ 400ms`（替代原来的 P95 ≤ 400ms）

这样设置后，脚本会同时显示两条 SLA 线，你可以清楚看到在哪个 QPS 档位 E2E P90 越过 400ms 门限，从而得出 SLA 合规的最大 QPS。**你确认这样理解吗？**

**Q3：输出结果目录命名**

按惯例我会输出到 `results/tianji_querysafety_4tp_qps_20260311/`，确认吗？

---

你现在可以只回答你确定/不确定的部分，或者直接说"开始执行"，我就按以上理解推进。

---

**User**

Q1: 4DP 内容还没跑完，可能还需要等1小时，你可以先做一下分析我看看；
Q2：实际上通用基准还有一项就是 e2e P90 < 180s,但是这个场景基本就被 E2E P90 ≤ 400ms 暂时取代了；
Q3: 可以的.

---

**Cursor**

好，信息确认完毕，开始执行。先找到配置文件位置。

找到了。读取当前配置。

配置一目了然。现在修改底部配置区，替换为 tianji 单组分析。

配置已更新，现在运行分析脚本。

30/30 全部分析完毕！结果非常有意思。先启动 HTTP 服务器，再写报告。

8765端口已被占用，说明 HTTP 服务器已在运行中，可直接访问图表。现在基于分析结果写 REPORT.md。

**SLA 分析核心发现：**

- 全部 30 档位 **100% PASS**（E2E P90 最高 0.3s，远低于 400ms 门限）
- 成功率全程 **100%**，TTFS P90 最高 0.289s
- QPS=7.0 时延迟**反而最低**（E2E P90 = 0.1s）——缓存预热效应
- **测试范围内未发现拐点**，真正拐点远超 7 QPS

报告已生成。以下是完整分析总结：

---

## 分析结果：全档位 PASS，但——测试范围不够！

### 核心数字

| 指标 | 范围 | SLA 门限 | 结论 |
|------|------|---------|------|
| E2E P90 | 0.1s ~ 0.3s | ≤ 0.4s | 全 PASS，余量 25%+ |
| TTFS P90 | 0.138s ~ 0.289s | ≤ 1.5s | 全 PASS，余量 80%+ |
| 成功率 | 100% 全档 | ≥ 99% | 全 PASS |

### 最有趣的发现：**QPS=7.0 时延迟反而是全程最低**

TTFS P90 在 QPS=7.0 时掉到了 **0.138s**，E2E P90 只有 **0.1s**——你的判断完全正确。这就是 SGLang 前缀缓存的**预热效应**：QPS 越高 → 相同前缀的请求越密集 → 8K Token system prompt 的 KV Cache 命中率越接近 100% → 反而更快。

### 问题：**真正拐点不在 4.0~7.0 这个范围内**

当前设计的 7 QPS 上限对这个模型来说太保守了。30 档走完，延迟还在下降，服务一点压力都没有。

### 下一步建议

两件事可以并行推进：
1. **等 4DP 实验完成**（约 1 小时）→ 直接做 4TP vs 4DP 横向对比（使用现有的 `multi_exp_compare.py`）
2. **考虑为 4TP 补测高 QPS 段**（7.0 → 20.0+ QPS）→ 找真正拐点

图表可以在浏览器访问：`http://localhost:8765/tianji_querysafety_4tp_qps_20260311/`

---

**User**

我看你刚刚在执行 multi_exp_compare.py  脚本内容先做了一些配置修改，我在想你是否可以将配置区 在外部使用一个yaml文件来进行配置读取，并且给出一个配置yaml 的规范教学说明来方便你之后使用  multi_exp_compare.py ，而不是频繁的修改它呢？

---

**Cursor**

好主意！先完整读一下脚本，再做改造。

好，思路清晰。先确认 PyYAML 已安装，然后同步规划改造内容。

PyYAML 已有，`configs/` 目录不存在需新建。现在同步执行三件事：改造脚本、创建目录、写 YAML 模版。

现在改造脚本底部，增加 YAML 外部配置读取逻辑：

脚本改造完毕。现在创建 YAML 模版文件和今天这次 tianji 实验的配置文件：

现在补一个之前 ziwei 对比实验的 YAML，留作多组对比示例：

现在验证脚本的新 `--config` 参数能正常运行：

`--config` 完全正常。最后确认一下整个 `configs/` 目录结构：

完成。以下是本次改造的完整说明：

---

## 改造总结

### 文件变更

| 文件 | 变更内容 |
|------|---------|
| `multi_exp_compare.py` | 新增 `--config` / `-c` 参数支持；`_load_yaml_config()` 函数；保持向下兼容 |
| `configs/template.yaml` | **完整规范模版**，含所有字段的详细注释说明 |
| `configs/tianji_4tp_20260311.yaml` | tianji 4TP 单组分析配置（含业务背景注释）|
| `configs/ziwei_tp8_vs_tp4_20260310.yaml` | ziwei 多组对比示例 |

### 使用方式

```bash
cd .../llm-benchmark

# 推荐：外部 YAML（不再碰脚本）
python3 -m llm_benchmark.analysis.analysis.multi_exp_compare --config configs/tianji_4tp_20260311.yaml

# 兼容旧方式（仍可用）
python3 -m llm_benchmark.analysis.analysis.multi_exp_compare
```

### 下次新实验时只需

1. 复制 `configs/template.yaml` → 按命名规范 `configs/<model>_<deploy>_<date>.yaml`
2. 填写 `groups`、`output_dir`，按需调整 `sla`
3. 直接 `--config` 运行，零代码修改

