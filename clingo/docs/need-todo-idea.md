# Need · TODO · IDEA

> 规划讨论文档 — 写于 2026-03-11，更新于 2026-03-12

---

## 一、NEED（已确认的真实痛点）

### N1. 数据处理链路无通用模板，换模型要重写参数

数据处理脚本（`process_*.py`、`make_peak100_stitched.py`、`fix_*.py`）的逻辑结构一致，但每次接新模型都要 copy-paste-modify：模型名、输入路径、目标 RPM。没有参数化骨架，容易改漏，也无法复用验证逻辑。

**解法**：提炼 `traffic-dataset-prep` Skill，沉淀数据处理方法论 + 脚本模式。

---

### N2. probe 脚本是模型行为探针，不是标准流程的一部分

当业务方没有提供数据时，用探针 query 反向推断模型用途（是分类/对话/安全拦截？）。业务数据有了之后走正常流程。

业务数据统一存放在 `/mnt/ai-infra/datasets`（正在逐步建设中）。

→ 暂不做 Skill，目前没有复用需求。

---

### N3. 分析截图环节存在结构化数据流失

完整的数据流：
```
data_analysis 处理业务数据
    ↓
平台部署新实例（手动，获得可调用 URL）
    ↓
speculative-decoding-benchmark 执行 benchmark 调用
    ↓
llm-benchmark analysis 工具生成 HTML 可视化报告
    ↓
浏览器截图 → 放入 results/ 对应目录
```

问题：HTML 报告中的结构化数据（请求粒度统计、TTFT 分布等）在截图后流失，无法跨模型对比。

**解法方向**：从 `llm_benchmark/analysis` 中间输出直接导出结构化数据，绕过截图。暂不做，等梳理分析流程时深入。

---

### N4. Skill 体系从零建设

`.cursor/skills/` 下目前只有通用的 `brainstorming`，没有针对本工程的专属 Skill。

**解法**：按路线图逐步建设（见 `skills/skills-roadmap.md`）。

---

## 二、TODO（按优先级排列）

### 立即执行

- [x] **T1** 创建 `traffic-dataset-prep` Skill ✅ 已验证（ziwei-32b / hepan-72b）
  - 同步把 `tmp/` 下 data 类脚本整理到 `scripts/data/`

- [ ] **T2** 创建 `clingo/docs/workflow/model-onboarding.md`
  - 将 ziwei 全流程提炼为标准 SOP

- [ ] **T3** 创建 `clingo/docs/workflow/reporting-template.md`
  - 基于 `results/ziwei_benchmark_20260310_163524/REPORT.md` 抽象模板

### 后续按流程推进

- [ ] **T4** `llm-deployment-docker` Skill（部署参数速查）— **当前优先**
- [x] **T5** `qps-benchmark-sweep` Skill ✅ 已验证（ziwei / tianji 实测）
- [ ] **T6** 梳理 `llm_benchmark/analysis` 中间输出，规划结构化导出方案
- [x] **T7** `benchmark-result-analysis` Skill ✅ 已完成（offline_analysis.py + PNG + REPORT 骨架，ziwei / hepan / tianji 多模型验证）
- [x] **T7.5** `llm-replay-benchmark` Skill ✅ 已验证（ziwei-32b poisson_100 + tianji-querysafety-4b peak30min，2026-03-12）
- [ ] **T8** `model-evaluation-workflow` Skill（顶层流程编排，依赖前面 Skill 稳定后）

---

## 三、IDEA（已筛选，去掉无用项）

### I1. model-card 模型档案（值得做）

为每个迁移模型维护一张"技术说明书"：

| 字段 | 内容 |
|------|------|
| 模型名称 / 版本 | - |
| 部署配置 | GPU 数量、TP/DP、端口、镜像 |
| 行为特征 | 探针测试总结（输出风格、响应时间、边界行为）|
| 压测结论 | 最大承载 QPS、TTFT P90 基线 |
| 已知问题 | 注意事项、坑点 |

与 `project_status.md` 无关（后者是 AI 会话工作记录）。放在 `clingo/docs/models/<model-name>.md`。

---

### I2. HTML Dashboard 分析可视化（多组对比部分已完成）

~~等 T6 时一起做~~ → **多组 QPS 对比可视化已实现**：`multi_exp_compare.py` 生成 3 个 HTML（QPS / Throughput / Latency 2D），支持 N 组对比、独立 legend 切换，沉淀为独立 `qps-sweep-comparison` Skill（含通用 SLA 基准 + 模型特定阈值）。

单实验 HTML 已由 `offline_analysis.py` 覆盖（benchmark-result-analysis Skill），并通过 `llm-replay-benchmark` Skill 串联完整回放→分析→报告闭环（ziwei-32b、hepan-72b、tianji-querysafety-4b 三个模型验证）。

剩余部分（T6 结构化数据导出、跨模型汇总 Dashboard）仍待建设。

---

## 四、已关闭的讨论项

| 项 | 结论 |
|----|------|
| Q5 init_model.py 生成器 | 关闭，没有实际需求 |
| N2 third_party 管理 | 软链接方式已满足需求，无需改动 |
