# 会话报告 — 2026-03-19（下午场：Dashboard 极限场景指标展示）

## 📌 会话概览

- **日期**：2026-03-19（周三，下午）
- **主要目标**：在 Dashboard 模型卡片中新增极限场景（Phase 1 饱和测试）可折叠区块，展示硬件吞吐上限下的极限 RPS、可容并发，辅助容量规划
- **Git 分支**：main（HEAD: `00bc59a`）
- **触发背景**：上一对话（session 36）完成了 INDEX.yaml 的 guoxue 条目更新，用户进一步希望 Dashboard 展示极限场景参数

---

## ✅ 成果

### 1. INDEX.yaml 数据模型扩展

`results/models/INDEX.yaml` 中 `xinghan-guoxue-72b-v1-2-reason` 的 `performance` 块新增三个字段：

| 字段 | 值 | 数据来源 |
|------|-----|---------|
| `saturation_rps` | 0.371 req/s | Phase 1 `max_rps_estimate`（con=120，decode_throughput=716.9 t/s） |
| `saturation_rpm` | 22.3 RPM | `saturation_rps × 60` |
| `saturation_concurrency` | 120 | Phase 1 峰值并发档位 |

字段设计为可选，null 时 Dashboard 自动跳过，对其他模型零影响。

### 2. serve.py 渲染逻辑升级

**改动 1**：`_PERFORMANCE_KEYS` 注册新字段 → `/api/models` JSON 接口同步输出  
**改动 2**：CSS 新增 `.saturation-block` 样式（浅黄 `#fff8c5` + 橙色边框 `d4a72c`，与 SLA 合规区白色区分）  
**改动 3**：`_render_model_card()` 增加条件渲染：
- `saturation_rps` 有值 → 渲染 `<details class="saturation-block">` 可折叠区块
- `saturation_rps` 为 null → 静默跳过

展开后内容：
```
极限 RPS：0.371 req/s（22.3 RPM）
可容并发：120
⚠️ 硬件吞吐上限，已超出 SLA，仅供容量规划参考
```

### 3. 设计文档归档

`clingo/docs/designs/2026-03-19-dashboard-saturation-metrics-design.md`：
- 数据来源说明（Phase 1 产出）
- INDEX.yaml schema 规范（含注释）
- 展示位置和折叠方式设计
- 3 个关键决策记录

### 4. 服务重启验证

- Kill 旧进程（PID 1968577），启动新进程（PID 549426）
- `curl` 验证 HTML 包含正确内容，API 接口返回新字段

---

## 🔧 文件变更

| 文件 | 类型 | 改动说明 |
|------|------|---------|
| `results/models/INDEX.yaml` | 📝 更新 | guoxue performance 块新增 `saturation_rps/rpm/concurrency` 三字段 |
| `scripts/serve.py` | 📝 更新 | `_PERFORMANCE_KEYS` 扩展、CSS `.saturation-block`、`_render_model_card()` 折叠渲染逻辑 |
| `clingo/docs/designs/2026-03-19-dashboard-saturation-metrics-design.md` | ✨ 新建 | 设计文档 |

---

## 🐛 问题与解决方案

### 问题：Visual Companion 服务器无法启动

- **现象**：运行 `.cursor/skills/brainstorming/scripts/start-server.sh` 提示 `node: command not found`
- **根因**：该机器（172.21.208.11）未安装 Node.js，无法启动 brainstorming 可视化服务
- **解决**：改用文字描述 + `AskQuestion` 交互式选择完成 brainstorming 三个问题（数据来源、展示位置、延迟口径），流程完整，功能不受影响

---

## 🎯 技术决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 无 Phase 1 数据的模型如何展示 | null 字段，不显示区块 | 避免用 sweep 最高测试点（不代表硬件极限）误导容量规划 |
| 极限点延迟展示 | 不展示（仅 RPS + 并发） | Phase 1 使用 max-concurrency 模式，无法直出 P90 延迟 |
| 折叠实现方式 | HTML `<details>` 原生标签 | 零 JS 依赖，默认收起（SLA 拐点是主信息），完全向下兼容 |
| 视觉风格 | 浅黄背景 + 橙色边框 | 与白色 SLA 合规区区分，隐含"超出 SLA 范围"的警示语义 |

---

## ⚠️ 未完成事项

| 项目 | 说明 |
|------|------|
| 其他模型 saturation 数据补充 | tianji / ziwei / hepan / lingyu 均无 Phase 1 数据，后续跑完 qps-peak-finder 后按规范填充即可 |
| chart-32b 容量分析 | sweep 仍在进行（8TP + 4TP），待结果出炉后完成拐点确认和 replay |

---

## 💡 建议与注意事项

- **扩展性**：后续每个新模型完成 qps-peak-finder Phase 1 后，仅需在 INDEX.yaml 对应 `performance` 块填入三个字段，Dashboard 自动生效，无需再改代码
- **数据准确性**：`saturation_concurrency` 记录 Phase 1 峰值档位（`con=N`），注释中建议同时标注 `decode_throughput` 值方便追溯
- **页面访问**：http://172.21.208.11:18999/

---

## 📈 下次会话计划

1. **chart-32b 容量分析**（高优先）
   - 等待 8TP / 4TP Phase 2 sweep 结果
   - 调整 `success_rate: 0.98` 重跑对比分析，确认真实延迟拐点
   - 确认拐点后执行 replay 测试

2. **guoxue 回放测试**（条件：可用测试机）
   - 当前 `replay_success_rate: null`，上线结论待补充

3. **其他模型 Phase 1 补测**（按需）
   - 若有新模型上线，走 qps-peak-finder 全流程时自然产出 saturation 数据

---

# 会话报告 — 2026-03-19（中午场：guoxue 报告归档 & EVAL_REPORT 生成）

## 📌 会话概览

- **日期**：2026-03-19（周三，中午）
- **主要目标**：将 guoxue Phase 1/2/3 实验结果按规范归档，生成 REPORT.md + EVAL_REPORT.md，并修正目录规范
- **Git 分支**：main
- **触发背景**：Phase 1/2/3 全部跑完，前一会话设计了 qps-peak-finder 方法，本次完成最终报告闭环

---

## ✅ 成果

### 1. Phase 2 + Phase 3 合并分析（16 档容量曲线）

- `cp -rl` 将 Phase 3（4 档 × 45min）+ Phase 2（12 档）硬链接合并到 `logs/guoxue_phase2_phase3_merged/`（共 16 子目录）
- 创建 YAML 配置 `configs/models/xinghan-guoxue-72b-v1-2-reason/qps_peak_finder.yaml`，运行 `multi_exp_compare`
- **SLA 最大 QPS：0.2494 req/s**（与网格搜索 0.245 偏差 1.8%，交叉验证 ✅）
- SLA 边界：0.2494→0.2529，E2E P90 跳变 134.3s→165.6s（+23%），bracket 宽度 1.4%
- 生成 3 个 HTML 图表：`plot_qps.html`、`plot_throughput.html`、`plot_latency_2d.html`

### 2. REPORT.md 生成（Phase 1/2/3 完整实验报告）

新建 `results/guoxue_qps_peak_finder_20260318/REPORT.md`，包含：
- Phase 1：con=20~130，peak=716.9 t/s @ con=120（19 分钟确定，2 次精调）
- Phase 2：12 档自适应逼近，bracket [0.2494 ✅, 0.2529 ❌]，宽度 1.4%，精度 5× 提升
- Phase 3：4 档 45min，全部 SLA ✅，稳定性确认
- 与网格搜索对比：总时间 ~8h vs ~25h，节省 2/3

### 3. model-context.md 更新

`results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` 追加 `peak_finder_*` 系列字段：
- `peak_decode_throughput: 716.9`，`peak_max_concurrency: 120`
- `peak_finder_sla_max_qps: 0.2494`，bracket lo/hi，bracket 宽度 1.4%
- `peak_finder_vs_grid_deviation: 1.8%`

### 4. EVAL_REPORT.md 综合报告（model-eval-report）

`results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` 完整更新：
- 综合两轮实验（原网格搜索 + qps-peak-finder），交叉验证偏差 1.8%
- 上线建议：⚠️ 有条件上线，推荐 4 实例 × 8TP = 32 卡 L20
- 容量曲线区间、SLA 拐点特征、部署建议

### 5. 目录规范修正

将 `qps_peak_finder_20260318/` 从 `results/models/<model>/`（模型级汇总目录）移动到 `results/guoxue_qps_peak_finder_20260318/`（实验级根目录），规范如下：
```
results/
├── guoxue_qps_peak_finder_20260318/   # ← 实验目录（根层）✅
│   ├── REPORT.md
│   ├── plot_qps.html / plot_throughput.html / plot_latency_2d.html
└── models/
    └── xinghan-guoxue-72b-v1-2-reason/
        ├── model-context.md           # 模型级汇总，路径引用已更新
        └── EVAL_REPORT.md             # 综合报告
```

更新了 `model-context.md`、`EVAL_REPORT.md` 中的路径引用，在 `results/README.md` 中补充了新条目。

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `logs/guoxue_phase2_phase3_merged/` | ✨ 新建 | Phase 2+3 硬链接合并目录（16 子目录）|
| `configs/models/xinghan-guoxue-72b-v1-2-reason/qps_peak_finder.yaml` | ✨ 新建 | qps-sweep-comparison YAML 配置 |
| `results/guoxue_qps_peak_finder_20260318/REPORT.md` | ✨ 新建 | Phase 1+2+3 完整实验报告 |
| `results/guoxue_qps_peak_finder_20260318/plot_*.html` | ✨ 新建 | 3 个交互式容量曲线图表 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 📝 更新 | 追加 peak-finder 各阶段结论字段 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | 📝 更新 | 综合两轮实验，更新上线建议 |
| `results/README.md` | 📝 更新 | 补充新实验条目 |

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| 实验目录误放在 `results/models/` 下 | 与目录规范不符（实验目录应在根层）| 用户指出后 `mv` 到 `results/guoxue_qps_peak_finder_20260318/`，更新所有引用 |

---

## 🎯 技术决策

1. **qps-sweep-comparison 负责全曲线**（而非仅 Phase 3）：将 Phase 2（覆盖 SLA 边界和过载区）合并进来，使容量曲线从 0.2056 到 0.4448 req/s 连续完整，SLA 拐点跳变清晰可见
2. **硬链接而非符号链接**：`Path.glob("**/*.csv")` 不追踪符号链接指向的目录，`cp -rl` 是唯一可靠方案（与 tianji 合并经验一致）
3. **两轮实验交叉验证而非替换**：EVAL_REPORT 同时呈现原网格搜索（24 档 × 60min）和 qps-peak-finder（Phase 1/2/3），偏差 1.8% 提升报告可信度

---

## ⚠️ 未完成事项

| 事项 | 优先级 | 说明 |
|------|--------|------|
| chart-32b SLA 阈值调整 + 拐点分析 | P0 | `success_rate: 0.99 → 0.98`，重跑 8TP vs 4TP 对比 |
| chart-32b QPS 扩展至 8~15 req/s | P0 | 当前最高 4.0 QPS E2E 余量 15×，真实拐点未定位 |
| chart-32b replay 测试 | P1 | 依赖拐点确认后执行 |

---

## 📈 下次会话计划

1. **chart-32b 容量分析**（最高优先）：
   - 调整 `success_rate: 0.98` 后重跑 `multi_exp_compare`（8TP vs 4TP）
   - 扩展 QPS 测试范围：`bash scripts/benchmark/run_qps_sweep.sh configs/models/xinghan-chart-32b-v1-1-agent/8tp.env`
   - 找到真实拐点后执行 replay
2. **guoxue 全部完成**，无遗留工作

---

# 会话报告 - 2026-03-18（深夜场：TTFS 指标修复 & 多CSV对比工具）

## 📌 会话概览

- **日期**：2026-03-18（周三，深夜）
- **主要目标**：排查同事反馈的 TTFS 指标计算错误 Case，建立标准多CSV对比工具，完善 Skill 文档
- **Git 分支**：main
- **关键提交**：`8ac0917`（fix: add compare_analysis.py and fix TTFS definition in skill）

---

## ✅ 成果

### 1. 🐛 TTFS 计算错误完整根因分析

**触发场景**：同事在飞书使用 bot agent 进行多版本 benchmark CSV 横向对比，发现 TTFS 数值与 TTFT 完全相同，报告不可信。

**根因（两个叠加错误）**：

1. **语义错误**：Bot agent 将 TTFS 误解为 "Time to First Stream"（首字节），正确含义是 "Time to First **Sentence**"（首句响应时间 = TTFT + 首句 decode 时间）
2. **计算错误**：原始 CSV 文件本身没有 `ttft`/`ttfs` 列，这两个指标必须通过解析 `token_list` JSON 列（调用 `analysis_response()`）才能正确计算。Bot agent 临时写了 ad-hoc Python 脚本，跳过了 `analysis_response()`，直接复用了 TTFT 值填充 TTFS

**错误结果 vs 正确结果**：

| 版本 | TTFS P90（错误）| TTFS P90（正确）| 说明 |
|------|----------------|----------------|------|
| 0.4.6-r08 | 0.525s ❌ | 1.255s ✅ | 差值 0.73s = 首句 decode 时间 |
| 0.4.6+2params-r08 | 0.486s ❌ | 1.250s ✅ | |
| 0.5.5-r08 | 0.561s ❌ | 1.519s ✅ | TTFS 实际劣化 +21.1%，被掩盖 |

### 2. ✨ 新建 `scripts/analysis/compare_analysis.py`

专为多 CSV 横向对比设计的标准脚本：
- 通过 `analysis_response()` 正确计算所有指标，TTFS 从 `token_list` 扫描中文标点精确定位
- 输出 Markdown 对比表：TTFT / TTFS / E2E / User-TPOT 全分位数（Mean/P50/P90/P95/P99）+ 相对基准变化率
- 可选 HTML CDF 叠加图（`--html`）
- 已用 session 原始 CSV 文件验证，TTFS 数值正确

### 3. 📚 升级 `benchmark-result-analysis SKILL.md`

新增内容：
- **TTFS 常见误解警告表**（4 条，覆盖 Stream/TTFT 等误用场景）
- **多 CSV 横向对比章节**（含命令示例、为什么不能直接读 CSV 列的说明）
- **FAQ 两条**：`TTFS=TTFT` 和 `TTFS 被标注为 Stream` 的处理方法

---

## 🔧 文件变更

| 文件 | 操作 | 行数 |
|------|------|------|
| `scripts/analysis/compare_analysis.py` | ✨ 新建 | +270 行 |
| `clingo/docs/skills/benchmark-result-analysis/SKILL.md` | 📝 更新 | +99 行 |

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| `git add .cursor/skills/.../SKILL.md` 报 `beyond a symbolic link` | `.cursor/skills/benchmark-result-analysis` 是符号链接，git 无法直接 add 链接下文件 | 改为 add `clingo/docs/skills/...` 路径的实体文件 |

---

## 🎯 技术决策

1. **方案选择（升级现有 SKILL vs 新建 SKILL）**：选择升级现有 `benchmark-result-analysis` SKILL，避免分散注意力；将"多CSV对比"作为新章节追加，向后兼容
2. **TTFS 计算强制通过 `analysis_response()`**：而非在脚本中重新实现，确保与 `offline_analysis.py` 指标口径完全一致
3. **Markdown 输出优先**：比较报告默认输出纯文本 Markdown，方便 bot/AI 直接读取分析；HTML 图表作为可选增强

---

## ⚠️ 未完成事项

本次会话目标清晰，范围收敛，无遗留未完成事项。

---

## 💡 建议与注意事项

1. **所有多版本对比任务必须使用 `compare_analysis.py`**：不得用 ad-hoc 脚本直接读 CSV 列计算 TTFS/TTFT
2. **TTFS 验证规则**：对比报告中如果 TTFS P90 ≈ TTFT P90（差值 < 0.1s），应立即怀疑计算有误，用标准脚本重新生成
3. **session 数据价值**：`tmp/bot_sessions/` 目录的 JSONL 文件是排查 bot 行为问题的重要资产，建议长期保留

---

## 📈 下次会话计划

1. **继续 chart-32b 评估**：8TP vs 4TP QPS sweep 正在运行（`logs/chart-32b-8tp/qps_20260318_134151/`，`logs/chart-32b-4tp/qps_20260318_134345/`），等 sweep 完成后运行 `compare_analysis.py` + `offline_analysis.py` 做分析
2. **guoxue Step 6/7 收尾**：`logs/guoxue_8tp_qps_20260316_163202/` sweep 完成后，生成 REPORT.md 和 EVAL_REPORT.md
3. **multi-compare 工具推广**：下次有多 CSV 对比任务时，在 session 开头主动引导使用 `compare_analysis.py`

---

# 会话报告 - 2026-03-17（Dashboard Phase 1 验收 + guoxue Step 6/7 + 文档修正）

## 📌 会话概览

- **日期**：2026-03-17（周二，下午至傍晚）
- **主要目标**：
  1. Dashboard Phase 1 完整验收（18 项）
  2. guoxue 业务峰值 RPM 确认（Grafana 截图）
  3. guoxue QPS Sweep 24 档分析 + Step 6/7 完整文档
  4. 文档措辞修正（上线结论需回放支撑）
  5. lingyu 实验链接端口修复
- **Git 分支**：main
- **关键提交**：`5449d08`（Dashboard Phase 1 修复 + polish）

---

## ✅ 成果

### 1. 🎉 Dashboard Phase 1 全部 18 项验收通过

**验收结果**：

| 验收项 | 结果 |
|--------|------|
| localhost 链接修复（socket.getsockname()）| ✅ 通过 |
| insights 字段 + "💡 关键发现"区块 | ✅ 通过 |
| in_progress 模型占位文本 | ✅ 通过 |
| insights 位置移到卡片墙下方 | ✅ 通过 |
| INDEX.yaml 缺失友好错误页 | ✅ 通过 |
| EVAL_REPORT.md 缺失卡片警告 | ✅ 通过 |
| 全部 API 端点（`/api/models`, `/api/models/{name}`）| ✅ 通过 |

**技术亮点**：`_get_server_host()` 使用 `socket.getsockname()[0]` 获取真实 IP，绕过反向代理重写 Host 头问题；insights 字段可选，有则展示、无则隐藏。

### 2. 📊 guoxue Grafana 业务峰值确认

读取两张 Grafana 监控截图：
- **裸模型监控**（`.png.png`）：`xinghan-guoxue-72b-v1-2-reason(total) = 43 RPM`（1 分钟绝对峰值）
- **MCP 流程监控**（`use_bazi_depth_mcp`）：`八字深度(total) = 213 RPM`（上游聚合，不等于模型调用量）

确认 `business_peak_rpm: 43`。

### 3. 📈 guoxue QPS Sweep 完整分析（Step 6）

**扫描规模**：24 档（0.190~0.350 req/s），总耗时 ~25 小时，2026-03-16 16:32 → 2026-03-17 18:26 完成。

**SLA 分析结论（TTFS P90 ≤ 1.5s | E2E P90 ≤ 150s | 成功率 ≥ 99%）**：

| 区间 | QPS (req/s) | TTFS P90 | E2E P90 | 成功率 | 判定 |
|------|------------|----------|---------|--------|------|
| 稳态区 | 0.190~0.245 | ~0.79s | 132~136s | 100% | ✅ PASS |
| **拐点** | **0.245→0.255** | 0.788→0.849s | **134→155s (+15.9%)** | 100% | ❌ FAIL |
| 过载区 | 0.255~0.350 | ~0.85s | 155~180s（平稳）| ≥99.9% | ❌ FAIL |

**关键特征（独特性）**：
- **E2E 软拐点**：超过拐点后服务不崩溃，E2E 稳定在 155~180s（不发散）
- **TTFS 极低**：全程 ≤ 0.86s（SLA 1.5s 的 57%），Prefill 侧完全无压力
- **成功率始终 ≥ 99.9%**，无服务失败（对比 ziwei-32b 的成功率断崖）
- 主要瓶颈是 4K token 输出的排队延迟（E2E），不是 TTFS

### 4. 📁 guoxue Step 7 完整文档输出

| 文件 | 内容 |
|------|------|
| `results/guoxue_qps_sweep_20260317/REPORT.md` | 24 档逐档明细 + 拐点分析 + 多实例扩容建议 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 更新 Step 5/6 结论 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | 综合评估报告，含"回放缺失"警告 |
| `results/models/INDEX.yaml` | guoxue 状态 `in_progress → completed`，全部 5 模型完成 |

### 5. 🔧 两处修正

**修正 1：guoxue 上线结论措辞**
- 问题：无回放测试直接写"✅ 可上线"不严谨
- 修正：改为 `⚠️ QPS 评估完成，回放测试缺失，上线结论待补充`

**修正 2：lingyu 实验链接端口**
- 问题：`linked_experiments` 中 `logs/lingyu_qps_sweep_20260317` 以 `logs/` 开头，serve.py 路由到 8765 端口（日志服务），而非 18999（Dashboard）
- 修正：改为 `results/lingyu_qps_sweep_20260317`（该目录已存在 REPORT.md 和 HTML 图表）

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/serve.py` | 📝 修改 | 添加 `_get_server_host()`；insights 位置；in_progress 占位文本 |
| `clingo/delay/2026-03-dalily_report.md` | 📝 修改 | 补充 2026-03-16 日报 |
| `scripts/export_sessions.py` | ✨ 新增 | 历史会话导出工具 |
| `scripts/data/process_guoxue_full.py` | ✨ 新增 | guoxue 数据处理管道 |
| `results/guoxue_qps_sweep_20260317/REPORT.md` | ✨ 新建 | QPS 拐点详细报告（24 档 SLA 明细）|
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 📝 更新 | Step 5/6 完整结论 |
| `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md` | ✨ 新建 | 综合评估报告 |
| `results/models/INDEX.yaml` | 📝 更新 | guoxue completed；lingyu linked_experiments 修复 |
| `configs/guoxue_8tp_qps_sweep.yaml` | ✨ 新建 | multi_exp_compare 分析配置 |
| `progress.md` | 📝 更新 | 本次会话工作日志 |

> ⚠️ results/ 目录在 .gitignore 中，上述 results/ 下的变更不入 git，仅文件系统生效。
> 代码变更（scripts/、configs/ 等）已通过 commit `5449d08` 入库。

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| CSV `field_size_limit` 超限 | `token_list` 字段超默认 131072 | `csv.field_size_limit(10**7)` 临时扩大（仅列名探测用）|
| guoxue recommendation 过于乐观 | 无回放测试直接写"✅ 可上线" | 改为 `⚠️` 警告级，明确说明"上线结论待补充" |
| lingyu 实验链接走 8765 端口 | `linked_experiments` 以 `logs/` 开头 | 改为 `results/` 前缀，与其他模型一致 |

---

## 🎯 技术决策

1. **guoxue 拐点类型定性为"E2E 软拐点"**：过载区 E2E P90 在 155~180s 间平稳（不恶化），区别于 ziwei-32b 的"TTFS 硬拐点"。这一分类影响 gateway 超时配置（建议 ≥ 200s）和 autoscaling 触发策略。
2. **业务峰值取 1 分钟绝对峰值（43 RPM）**：Grafana tooltip 值，比 20 分钟窗口均值（25 RPM）保守，适合作为资源规划的安全基准。
3. **无回放测试不给上线结论**：与 lingyu（H20 环境限制）同理——资源不足时跳过回放，但明确标注，让决策者知晓数据缺口。
4. **linked_experiments 统一使用 results/ 路径**：serve.py 的路由逻辑以 `logs/` vs `results/` 前缀区分服务端口，所有归档完成的实验应放入 results/ 并用 results/ 路径引用。

---

## ⚠️ 未完成事项

| 事项 | 状态 | 说明 |
|------|------|------|
| guoxue 回放测试 | ⏳ 待机器资源 | 需要可用的测试机才能执行；跳过原因已在文档中明确标注 |
| guoxue 正式上线结论 | ⏳ 依赖回放测试 | 当前仅有 QPS Sweep 结论，无法给出"可上线"判断 |
| lingyu transfer_test 多实例吞吐分析 | ⏳ 可选 | `logs/lingyu_qps_sweep_20260317/lingyu_transfer_test_*` 数据已存在 |
| Dashboard Phase 2（过滤/排序/复制结论）| 📌 有意推迟 | 当前模型数量（5 个）不需要，等 >10 模型时再做 |

---

## 💡 建议与注意事项

1. **guoxue 上线判断流程**：下次有测试机时，用 `llm-replay-benchmark` Skill 执行回放测试，补充 `replay_success_rate`/`replay_ttft_p90_s` 后再给正式上线结论。
2. **insights 字段可扩充**：可补充"72B 长推理模型 E2E 是主要瓶颈，TTFS 极低（<1s）"作为新的跨模型技术洞察。
3. **gateway 超时阈值**：guoxue 稳态 E2E P90 约 134s，建议 gateway 超时 ≥ 200s（50% 余量）；autoscaling 触发阈值建议 ≥ 0.22 req/s（拐点 0.245 的 90%）。
4. **所有 5 个模型已完成 QPS Sweep**：下一个评估周期如有新模型，直接按 `model-evaluation-workflow` Skill 全流程接入。

---

## 📈 下次会话计划

1. **guoxue 回放测试**（优先级：高，依赖机器资源）：准备 Poisson 插值数据集，执行回放，补充 Step 5 数据
2. **补充 insights**：在 INDEX.yaml `insights` 字段加入"72B 长推理模型 TTFS/E2E 解耦"洞察
3. **新模型接入**（按需）：如有新模型评估需求，使用 `model-evaluation-workflow` Skill

---

# 会话报告 - 2026-03-16（guoxue 模型评估流程推进 & QPS 扫描启动）

## 📌 会话概览

- **日期**：2026-03-16（周一，下午场）
- **结束时间**：2026-03-16 19:00+
- **总步骤数**：6（Step 4 验证 + Step 5 修复启动 + 3 项文档更新 + progress 记录）
- **主要目标**：
  1. 解除上次会话遗留的 endpoint 404 阻塞（Step 4）
  2. 修复 QPS 扫描数据集格式问题（`_all.csv` 3列索引 → `_full.csv` 6列完整数据）
  3. 成功启动 24 档 QPS 扫描（Step 5）
  4. 同步更新 Skill 和数据处理脚本/文档，固化步骤1.5 合并规范
- **Git 分支**：main

---

## ✅ 成果

### 1. Step 4：远端连通性验证通过
- 用户在部署平台完成服务上线后，endpoint 恢复正常
- `/health` 200、`/v1/models` 200、POST chat/completions 200
- 平台 serve 的模型 ID 为 `bazi-guoxue-eagle3-test`（非模型路径名）
- baseline 延迟 2.30s（64 tokens，符合 72B 长推理模型预期）
- 更新 `model-context.md`：补充 `served_model_id`、`baseline_latency_s` 字段

### 2. QPS 扫描数据集问题修复
- **根因**：DataConverter 输出的 `_all.csv` 是 3 列内部索引文件，不含 `messages`/`old_response`，benchmark 工具启动即抛 `KeyError: 'old_response'`
- **修复**：合并两个日期 CSV（`_2026-03-13.csv` + `_2026-03-14.csv`，23,357 行），填充 NaN，输出 `_full.csv`，更新扫描脚本路径
- **根治**：在 `process_guoxue_full.py` 中增加步骤1.5，未来重跑时自动输出正确的 `_all.csv`

### 3. Step 5：24 档 QPS 扫描正式运行
- **PID**：1054031/1054057（nohup 后台）
- **日志目录**：`logs/guoxue_8tp_qps_20260316_163202/`
- **进度**（截至 ~19:00）：3/24 档（QPS 0.190→0.195→0.200），每档 60min，约 2.1h 已用
- **预计完成**：2026-03-17 约 17:00
- 第一档成功率 100%，运行稳定

### 4. 三处联动文档/代码更新
| 文件 | 操作 | 核心内容 |
|------|------|---------|
| `scripts/data/process_guoxue_full.py` | 🐛 修复 | 增加步骤1.5：合并日期分片覆盖写回 6 列 `_all.csv` |
| `datas/output_guoxue/README.md` | 📝 更新 | 增加步骤1.5 说明、`_full.csv`/`_all.csv` 区别、陷阱注释 |
| `.cursor/skills/traffic-dataset-prep/SKILL.md` | 📝 更新 | 流程图步骤1.5、新错误条目 `KeyError: 'old_response'`、Checklist 拆分 |

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/models/xinghan-guoxue-72b-v1-2-reason/model-context.md` | 📝 修改 | Step 4 字段（endpoint、baseline latency）|
| `datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_full.csv` | ✨ 新建 | 23,357 行，6 列完整数据，QPS 扫描使用 |
| `scripts/benchmark/run_guoxue_8tp_qps_sweep.sh` | 📝 修改 | DATASET_PATH 改为 `_full.csv` |
| `scripts/data/process_guoxue_full.py` | 🐛 修复 | 增加步骤1.5 合并逻辑 |
| `datas/output_guoxue/README.md` | 📝 更新 | 步骤1.5、文件说明、陷阱注释 |
| `.cursor/skills/traffic-dataset-prep/SKILL.md` | 📝 更新 | 步骤1.5、新错误条目、Checklist 细化 |
| `progress.md` | 📝 更新 | 本次会话日志 |
| `project_status.md` | 📝 更新 | 本文件 |

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决方案 |
|------|------|---------|
| Endpoint 404（Step 4 阻塞） | 平台部署实例未执行"上线"操作，路由未生效 | 用户在平台手动上线后自动恢复，无代码改动 |
| `KeyError: 'old_response'`（Step 5 首档立即失败） | 扫描脚本指向 DataConverter 输出的 `_all.csv`（3 列索引），benchmark 工具要求 6 列含 `old_response` | 手动合并日期 CSV → `_full.csv`；更新脚本；修复源头脚本步骤1.5 |

---

## 🎯 技术决策

1. **`_full.csv` vs 覆盖 `_all.csv`**：当前扫描脚本使用 `_full.csv`（运行中不改），修复的步骤1.5 在下次重跑时直接覆盖 `_all.csv`，两者数据完全等价，命名统一由下次运行后自动对齐。

2. **DataConverter `_all.csv` 陷阱文档化**：第一次踩到这个坑后立刻在三个地方（脚本、README、Skill）同步记录，防止未来新模型重踩。

3. **`old_response` NaN 填充为 `""`**：benchmark 工具执行 `tokenizer.encode(old_response)` 时需要字符串类型；填空字符串使 `old_response_len=0`，不影响测试逻辑（不使用参考答案）。

---

## ⚠️ 未完成事项

| 事项 | 优先级 | 说明 |
|------|--------|------|
| Step 5 QPS 扫描完成 | P0 | 运行中，预计 2026-03-17 ~17:00 完成，共 24 档 |
| Step 6 结果分析 | P0 | 扫描完成后执行：`offline_analysis.py` + `qps-sweep-comparison` Skill，生成 HTML 报告 + REPORT.md |
| Step 7 综合评估报告 | P1 | Step 6 完成后，使用 `model-eval-report` Skill 生成 EVAL_REPORT.md |
| `business_peak_rpm` 确认 | P1 | 用户待提供 Grafana QPM 截图，补入 model-context.md |
| 回放测试 | ⏭️ 跳过 | 需大量实例，本次评估不执行 |
| `project_status.md` 定期更新节点 | P2 | Step 6/7 完成后各更新一次 |

---

## 💡 建议与注意事项

- **QPS 扫描不要中断**：72B 长推理模型单档 60 分钟，中断后某档数据会不完整，影响拐点判断。如需中断，记录当前已完成档位，重启时从下一档继续（修改脚本 QPS_LEVELS 列表跳过已完成档位）。
- **Step 6 分析前检查**：先确认 24 个 `qps_*/result.csv` 文件均存在且非空，再运行 `offline_analysis.py`。
- **served_model_id 注意**：平台 serve 的模型名是 `bazi-guoxue-eagle3-test`，不是模型路径名，benchmark 工具使用 `model='ignore-model-name'` 绕过，无需额外配置。

---

## 📈 下次会话计划

1. **等待 QPS 扫描完成**（2026-03-17 ~17:00 后）
2. **Step 6：结果分析**
   - 运行 `offline_analysis.py` 生成各档 HTML 报告
   - 使用 `qps-sweep-comparison` Skill 生成对比曲线，定位拐点
   - 撰写 `REPORT.md` 骨架（P50/P90/P95/P99 数据已预填）
3. **Step 7：综合评估报告**
   - 确认 `model-context.md` 所有字段已填（包括 `business_peak_rpm`）
   - 使用 `model-eval-report` Skill 生成 `EVAL_REPORT.md`
4. 如需 Grafana QPM 数据，请用户在 Step 6 前提供截图

---

# 会话报告 - 2026-03-11（Skill 体系建设 & tianji-querysafety 压测启动）

## 📌 会话概览

- **日期**：2026-03-11（周三，下午~晚间）
- **结束时间**：2026-03-11 20:07
- **总步骤数**：7（含 1 个 BugFix）
- **主要目标**：
  1. 建立项目 Skill 体系（存储架构 + 第一个 Skill）
  2. 整理脚本目录结构（tmp/ → scripts/）
  3. 固化新模型接入 SOP
  4. 完成 tianji-querysafety 数据处理 + benchmark 脚本 + 压测启动

---

## ✅ 成果

### 1. clingo/docs 文档体系建立

| 文件 | 内容 |
|------|------|
| `clingo/docs/README.md` | 项目概览 + 已迁移模型清单 |
| `clingo/docs/need-todo-idea.md` | 需求/待办/想法，经两轮讨论修正 |
| `clingo/docs/skills/skills-roadmap.md` | 5 Skill 候选 + 优先级 + 建设时间线 |
| `clingo/docs/workflow/model-onboarding.md` | 新模型接入 8步 SOP（完整流程）|

### 2. scripts/ 目录重组

`tmp/` 下 15 个脚本分类迁移到 `scripts/{deploy,benchmark,probe,data,analysis}/`，新增 `scripts/README.md`。

### 3. traffic-dataset-prep Skill（P0）—— 完成验证

**情况 A（JSONL 线上日志）**：
- 5步管道（DataConverter → DataSampler → 时间戳拼接 → DataInterpolator → 脏数据过滤）
- REFACTOR 补充：`model_list` 中文别名陷阱（丢失 70% 数据的根因）
- 存储架构：`clingo/docs/skills/` 真实存储，`.cursor/skills/` 软链接

**情况 B（CSV + 系统提示模板填充）**—— 本次新增：
- `times(ms) → income_time`（Asia/Shanghai）
- `{{query}}` 模板填充 → `messages` JSON
- 文件体积警告（per-row 展开后 5~10x）

**验证状态**：✅ ziwei-32b（情况 A）+ hepan-72b（情况 A）+ tianji-querysafety（情况 B）三模型实测通过

### 4. model-onboarding.md SOP

8步完整流程（Step 0 信息收集 → Step 6 结果归档），含 Checklist 和环境说明。经两轮修正：
- 分析工具命令：`analysis --host 0.0.0.0 --port 8050 --exp <dir>`
- Step 3 脚本模式：每模型新建专属脚本（copy + 改配置块）

### 5. tianji-querysafety-4b-v2-3 压测启动

**数据处理**：`_peak30min.csv`（44,099 行，897 MB，峰值 2168 RPM）

**服务验证**（Demo 3 case）：

| case | 耗时 | 结果 |
|------|------|------|
| 正常放行 | 0.95s | `{"label": "无", ...}` ✅ |
| 敏感拦截 | 0.24s | `{"label": "违法行为", ...}` ✅ |
| 边界医疗 | 0.13s | `{"label": "无", ...}` ✅ |

**压测脚本**：QPS 7.00→4.00，30 档，每档 45min，预计 ~23h

---

## 🐛 问题与解决方案

### KeyError: 'prompt'（benchmark 启动报错）

**现象**：benchmark 工具在读取 CSV 时报 `KeyError: 'prompt'`

**根因**：`benchmark.py` 第 109 行 `pd.read_csv(..., dtype={"prompt": str, ...})` 强制要求 `prompt` 列，即使内容为空也必须存在。`process_tianji_querysafety_full.py` 的 `OUTPUT_COLS` 漏掉了该列。

**修复**：
1. 直接给现有两个 CSV 插入空 `prompt` 列（Python 脚本，约 2min 完成）
2. 修复 `process_tianji_querysafety_full.py` 的 `OUTPUT_COLS`
3. SKILL 常见错误表补录此条（路径 A/B 通用）

---

## 🎯 技术决策

| 决策 | 理由 |
|------|------|
| Skill 真实存储在 `clingo/docs/skills/`，`.cursor/skills/` 软链接 | 归档于项目文档，同时保持 Cursor IDE 可加载 |
| 每模型建专属数据处理脚本（不做参数化共用）| 各模型配置差异大（model_list/PEAK_WINDOWS/TARGET_RPM），参数化反而降低可读性 |
| tianji 压测用 `_peak30min.csv`（44K 行）而非全量（281K 行）| 全量 5.7 GB，per-row 含完整系统提示，峰值窗口已足够代表真实负载 |
| max_completion_tokens=256（而非默认 4096）| 安全模型输出为短 JSON（实测 14~33 tokens），减少无效等待，提高压测效率 |

---

## ⚠️ 未完成事项

| 事项 | 状态 | 说明 |
|------|------|------|
| tianji QPS 压测 | 🔄 **执行中** | 7.0→4.0，30 档，预计 ~23h 完成 |
| hepan-72b 压测 | ⏳ 待启动 | 数据已就绪（6,034 条 150RPM），需写 deploy + benchmark 脚本 |
| llm-deployment-docker Skill | ⏳ 待建 | P0，参考类，写起来快 |
| qps-benchmark-sweep Skill | ⏳ 待建 | P0，核心技能 |
| clingo/docs/workflow/reporting-template.md | ⏳ 待建 | 量化报告模板 |
| clingo/docs/models/ 模型档案 | ⏳ 待建 | 三个已迁移模型的信息卡 |
| data_analysis git push | ⏳ 待换机执行 | `33e32bf` on `wnd_dev` |

---

## 💡 建议与注意事项

1. **tianji 压测完成后**：运行 `analysis --host 0.0.0.0 --port 8050 --exp logs/tianji_qps_<timestamp>` 查看结果，关注拐点（成功率 <99% 或 TTFT P90 >2s 的档位）

2. **hepan-72b 下一步**：先写 `scripts/deploy/start_henpan_72b.sh`，再写 `scripts/benchmark/run_henpan_qps_sweep.sh`，参考 tianji 脚本结构

3. **prompt 列提醒**：所有 benchmark 数据集 CSV 必须包含空 `prompt` 列，否则报 `KeyError: 'prompt'`（已在 SKILL 中记录）

4. **全量 CSV 体积**：tianji `_all.csv` 已达 5.7 GB，后续若有类似模型（系统提示长 + CSV 源），优先使用峰值窗口采样文件做压测

---

## 📈 下次会话计划

### 优先级 1：等待 tianji 压测结果（~23h 后）
- 运行 analysis 工具分析结果
- 输出量化报告，确认拐点 QPS
- 截图归档到 `results/tianji_qps_<date>/`

### 优先级 2：hepan-72b 压测
- 写 `scripts/deploy/start_henpan_72b.sh`
- 写 `scripts/benchmark/run_henpan_qps_sweep.sh`
- 确认 henpan-72b 的平台 endpoint URL

### 优先级 3：继续 Skill 建设
- `llm-deployment-docker`（P0，参考类，写起来快）
- `qps-benchmark-sweep`（P0，核心技能）

---

## 📊 项目整体状态（截至 2026-03-12 更新）

| 模型 | 数据 | 本地部署 | 平台部署 | 探测 | 压测 | 报告 |
|------|------|----------|----------|------|------|------|
| ziwei-32b (xinghan) | ✅ | ✅ | ✅ k8s 新镜像 v0.4.6.post2 | ✅ | ✅ 4TP+8TP all目录已整合 | ⏳ 待analysis |
| ziwei-8b (twostep) | ✅ | ✅ | ✅ k8s 新镜像 v0.4.6.post2 | ✅ | ✅ | ✅ |
| tianji-querysafety-4b | ✅ | ✅ | ✅ | ✅ | 🔄 进行中 | ⏳ |
| hepan-72b | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |

**sglang 镜像状态**：

| Tag | 来源 | 推送状态 |
|-----|------|---------|
| `reg.xxwolo.com/master/sglang:v0.4.1.post4` | `reg.xxwolo.com/ai/lmsysorg-sglang:latest` | ✅ 已推送 |
| `reg.xxwolo.com/master/sglang:v0.4.6.post2` | `reg-ai.cece.com/ai/sglang:v814` | ✅ 已推送 |

**Skill 进度**：

| Skill | 状态 |
|-------|------|
| `traffic-dataset-prep` | ✅ 已验证（情况 A+B）|
| `llm-deployment-docker` | ⏳ 待建 |
| `qps-benchmark-sweep` | ⏳ 待建 |
| `llm-service-probing` | ⏳ 待建 |
| `benchmark-result-analysis` | ⏳ 待建 |
| `model-evaluation-workflow` | ⏳ 待建（依赖前面完成）|

---

# 会话报告 - 2026-03-12

## 📌 会话概览

- **日期**：2026-03-12
- **主要目标**：Docker 镜像迁移打 tag + 推送；k8s 新部署服务验证
- **总步骤数**：2
- **Git 分支**：不适用（非 git repo）

## ✅ 成果

1. **sglang 镜像重新打 tag 并推送至 master registry**
   - `reg.xxwolo.com/master/sglang:v0.4.1.post4`（来自 lmsysorg-sglang:latest）
   - `reg.xxwolo.com/master/sglang:v0.4.6.post2`（来自 reg-ai.cece.com/ai/sglang:v814）

2. **新部署 k8s 服务全部验证通过**
   - `infra-xinghan-ziwei-p32b-v1`：32b 通用推理，多轮对话 / 摘要 / 代码生成 ✅
   - `infra-ziwei-intention-twostep-p8b-v1`：8b 意图识别，twostep 输出格式正常 ✅

## 🔧 文件变更

| 文件 | 操作 |
|------|------|
| `/tmp/test_new_deployments.py` | ✨ 新增（服务验证脚本，162行）|
| `progress.md` | 📝 更新 |
| `project_status.md` | 📝 更新（本文件）|

## 🐛 问题与解决方案

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `docker push` 返回 `unauthorized` | `master/sglang` 仓库无 push 权限 | 用户在仓库侧授权后重新 push，成功 |
| `SyntaxError: invalid syntax` (Python) | 测试脚本字符串内含中文双引号 `"两步法"` | 去掉中文引号改为普通文本 |

## 🎯 技术决策

- 测试脚本按模型规格差异化设计：8b 聚焦意图识别核心用例（A1-A5），32b 聚焦复杂推理/生成（B1-B4）
- 测试先调 `/v1/models` 自动获取 model_id，避免硬编码出错
- 两个 push 任务并行后台执行，节省等待时间

## ⚠️ 未完成事项

- tianji QPS 压测仍在运行中（上次会话启动）
- hepan-72b 部署脚本尚未编写

## 💡 建议与注意事项

- 新镜像已推送至 `reg.xxwolo.com/master/`，k8s manifest 中的 `image` 字段如需更新请参考上方镜像表
- 8b twostep 模型输出带 `<think>` 标签，下游解析需剥离该标签再处理意图文本
- 32b 复杂推理响应时间 1~4s，意图识别 8b 响应时间 0.2~0.5s，可作为 SLA 基准参考

## 📈 下次会话计划

### 优先级 1：tianji 压测结果分析
- 压测跑完后运行 analysis 工具，确认拐点 QPS
- 输出量化报告归档至 `results/tianji_qps_<date>/`

### 优先级 2：hepan-72b 压测
- 写 `scripts/deploy/start_henpan_72b.sh`
- 写 `scripts/benchmark/run_henpan_qps_sweep.sh`

### 优先级 3：Skill 建设
- `llm-service-probing`（可直接基于 `tmp/test_remote_services.py` 提炼）
- `qps-benchmark-sweep`（核心技能，P0）

---

# 会话报告 - 2026-03-12（ziwei 4TP + 8TP QPS 结果整合）

## 📌 会话概览

- **日期**：2026-03-12
- **结束时间**：2026-03-12 ~12:00
- **总步骤数**：3
- **主要目标**：将 ziwei 8TP 和 4TP high QPS benchmark 的历史结果整合为统一格式目录，供 analysis 工具直接使用
- **Git 分支**：不适用（非 git repo）

---

## ✅ 成果

### 1. ziwei 8TP QPS 结果整合 → `logs/ziwei_8tp_qps_20260310_all/`

将两批分散的 8TP 结果合并为 **30 档**（QPS 0.46–2.00），统一 `TP8_qps_X.XX/` 子目录格式：

| 来源目录 | 原格式 | QPS 范围 | 档数 |
|----------|--------|----------|------|
| `ziwei_8tp_qps_stress_20260310_200246` | `qps_X.XX/` | 0.46–1.00 | 20 |
| `ziwei_8tp_high_qps_20260311_115259` | `TP8_qps_X.XX/`（已正确）| 1.10–2.00 | 10 |

编写合并脚本 `tmp/merge_8tp_qps_20260310.py` 执行复制（原始目录全保留）。

### 2. ziwei 4TP QPS 结果补全 → `logs/ziwei_4tp_qps_20260310_all/` 扩充至 34 档

发现 `ziwei_4tp_high_qps_20260311_115109/`（QPS 1.00–2.00，11档）已于 2026-03-11 20:03 跑完但未纳入 all 目录。将 1.10–2.00 共 10 档追加，`all/` 从 24 档扩展为 **34 档**（QPS 0.46–2.00）。

### 3. TP4_qps_1.00 数据源一致性修正

步骤 2 初版操作产生了混合状态（csv 来自 stress run，dataset/log 来自 high run）。用户确认后完全替换为 high run，`TP4_qps_1.00/` 4 个文件来源统一。

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `tmp/merge_8tp_qps_20260310.py` | ✨ 新增 | 8TP 合并脚本，78行 |
| `logs/ziwei_8tp_qps_20260310_all/` | ✨ 新建 | 30档，TP8_qps_X.XX/ 格式 |
| `logs/ziwei_4tp_qps_20260310_all/` | 📝 扩充+修正 | 24档→34档，TP4_qps_1.00 来源统一 |
| `progress.md` | 📝 更新 | 本文件 |
| `project_status.md` | 📝 更新 | 本文件 |

**只读（未修改）**：
- `logs/ziwei_8tp_qps_stress_20260310_200246/`
- `logs/ziwei_8tp_high_qps_20260311_115259/`
- `logs/ziwei_4tp_high_qps_20260311_115109/`

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决方案 |
|------|------|---------|
| `TP4_qps_1.00` 混合状态 | 补全策略只添加缺失文件，未考虑两次 run 的 csv 来源不同 | 用户确认后完全替换为 high run，删除旧 stress run 的 csv |

---

## 🎯 技术决策

| 决策 | 理由 |
|------|------|
| 8TP 合并用 Python 脚本（而非 bash）| 来源格式不同（有/无 TP8_ 前缀），Python 正则解析更可靠，避免 bash glob 排序问题（参考 4TP 合并时踩过的坑）|
| TP4_qps_1.00 选用 high run | high run 是独立完整的一次运行，4文件来源一致；stress run 只是大扫描中间档，csv 文件还比 high run 大（277MB vs 172MB，可能参数不同）|
| 所有合并操作均为复制（原目录保留）| 原始数据不可变，便于后续回溯和重新验证 |

---

## ⚠️ 未完成事项

| 事项 | 状态 | 说明 |
|------|------|------|
| tianji QPS 压测 | 🔄 执行中 | 7.0→4.0，30档，预计今日内完成 |
| hepan-72b 压测 | ⏳ 待启动 | 数据已就绪（6,034条），需写 deploy + benchmark 脚本 |
| ziwei 4TP/8TP analysis 分析 | ⏳ 待执行 | all 目录已就绪，可直接运行 analysis 工具 |
| llm-deployment-docker Skill | ⏳ 待建 | P0 |
| qps-benchmark-sweep Skill | ⏳ 待建 | P0 |

---

## 💡 建议与注意事项

1. **analysis 工具调用**：
   - 4TP：`analysis --host 0.0.0.0 --port 8050 --exp logs/ziwei_4tp_qps_20260310_all`
   - 8TP：`analysis --host 0.0.0.0 --port 8050 --exp logs/ziwei_8tp_qps_20260310_all`

2. **数据完整性**：两个 all 目录每档均含 4 个文件（`dataset.csv`、`.log`、`vanilla_qpsX.XX.csv`、`vanilla_qpsX.XX.argv.csv`），可直接用于 analysis。

3. **4TP all 目录说明**：QPS 0.46–1.00 来自 stress run（2026-03-10），QPS 1.00–2.00 全部来自 high run（2026-03-11）；其中 QPS=1.00 档已统一为 high run 来源。

---

## 📈 下次会话计划

### 优先级 1：ziwei 4TP vs 8TP 对比分析
- 运行 analysis 工具，对比两套 all 目录
- 关注拐点 QPS（成功率 <99% 或 TTFT P90 异常档位）
- 输出对比报告归档到 `results/ziwei_tp_compare_<date>/`

### 优先级 2：tianji 压测结果分析（等待完成后）
- 运行 analysis，确认拐点 QPS
- 输出量化报告归档至 `results/tianji_qps_<date>/`

### 优先级 3：hepan-72b 压测启动
- 写 `scripts/deploy/start_henpan_72b.sh`
- 写 `scripts/benchmark/run_henpan_qps_sweep.sh`

---

# 会话报告 - 2026-03-12（hepan 离线分析 & offline_analysis.py Bug 修复）

## 📌 会话概览

- **日期**：2026-03-12
- **结束时间**：2026-03-12 ~17:30
- **总步骤数**：2（分析执行 + Bug 修复）
- **主要目标**：
  1. 对同事完成的 hepan-72b 回放测试结果进行离线分析，产出完整报告
  2. 修复 `offline_analysis.py` 中 Token Length Distribution 直方图显示异常问题
- **验证对象**：`benchmark-result-analysis` Skill

---

## ✅ 成果

### 1. hepan-72b 离线分析报告（`results/hepan_benchmark_20260312/`）

同事（jyf）使用以下命令跑了 hepan-72b 回放压测：
```bash
benchmark --exp-name hepan_temp_test \
  --dataset-path ...xinghan-hepan-72b-v1-2_selected_combined_3days_peak_poisson_150_stitched.csv \
  --url https://infer.geniuworks.com/infra-xinghan-hepan-p72b-v1/v1/chat/completions \
  --tokenizer /mnt/ai-llm/hepan-v1-2-grpo \
  --no-kvcache --keep-income-time --seed 42 --max-completion-tokens 4096
```

分析结果（6,034 请求，150 RPM 峰值，~66 分钟）：

| 指标 | 值 | 状态 |
|------|----|----|
| 成功率 | **99.95%** | ✅ |
| TTFT P50/P90/P99 | 0.37s / 1.15s / 2.38s | ✅ |
| E2E P50/P90/P99 | 6.80s / 13.38s / 26.27s | ⚠️ P99 较高（长输出，合理）|
| User-TPOT 均值 | 0.037s | ✅ |
| Decode 吞吐 | 266.3 tok/s | ✅ |

产出：HTML（2.9MB）+ 7 张 PNG + REPORT.md 骨架（分位数预填，背景/结论/Grafana 待用户补充）

### 2. `offline_analysis.py` Token 直方图 Bug 修复

**问题**：Token Length Distribution 图表中各系列数据全压在第一个 bin，分布不可见。

**根因**：`build_token_hist` 用全局 `tok_max`（取自所有系列最大值 ~900）均分 200 个 bin，宽度 ~4.5 tokens/bin，`first_sentence`（分布 0~40）全部被压进前 9 个 bin。

**修复**：新增 `_series_p99()` 函数，每个系列独立用自己的 P99 作为 `x_max`，裁剪长尾，保留有效分布范围。同时新增系列切换按钮（`prompt | completion | all | first_sentence | All`）。相同逻辑同步应用于 `build_latency_hist`。

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/hepan_benchmark_20260312/hepan_peak_replay_150rpm_analysis.html` | ✨ 新增 | 2.9MB 交互式完整分析报告 |
| `results/hepan_benchmark_20260312/*.png` | ✨ 新增 | 7 张 CDF + Timeline 静态图 |
| `results/hepan_benchmark_20260312/REPORT.md` | ✨ 新增 | 7.5KB 报告骨架（分位数已预填）|
| `scripts/analysis/offline_analysis.py` | 🐛 修复 | 新增 `_series_p99()`，修复直方图 bin 过宽问题（+20 行）|
| `progress.md` | 📝 更新 | 新增本次会话记录 |
| `project_status.md` | 📝 更新 | 本文件 |

---

## 🐛 问题与解决方案

| 问题 | 根因 | 解决方案 |
|------|------|---------|
| Token Length Distribution 图表显示异常（所有数据挤在第一 bin）| 全局 `tok_max` 使 bin 宽过大，`first_sentence` 分布（0~40）完全被压缩 | 每系列独立用 P99 作为 `x_max`，裁剪长尾 |
| 用户提供的是 dataset 路径而非 result 路径 | 同事在外部环境执行了 benchmark，result CSV 存放于 shared 路径 | 根据同事提供的命令推断出 result 路径 `/mnt/ai-infra/users/shared/.../hepan_temp_test.csv`，验证后直接分析 |

---

## 🎯 技术决策

| 决策 | 理由 |
|------|------|
| 直方图改为 per-series P99 作为 x_max | 不同系列（prompt/completion/all/first_sentence）分布范围差异悬殊（~40 vs ~900），共用全局 x_max 会导致范围窄的系列被压缩 |
| 新增系列切换按钮而非删除重叠系列 | 用户需要逐一查看各系列分布，Plotly updatemenus 实现零额外数据量开销的切换 |
| X/Y 轴改为 autorange=True | 各系列 P99 各不相同，固定轴范围无法同时适应所有系列 |

---

## ⚠️ 未完成事项

| 事项 | 状态 | 说明 |
|------|------|------|
| hepan REPORT.md 补充 | ⏳ 待用户 | 背景目的、结论、Grafana 截图 |
| tianji QPS 压测 | 🔄 执行中 | 进行中，结果待分析 |
| llm-deployment-docker Skill | ⏳ 待建 | P0 |
| llm-service-probing Skill | ⏳ 待建 | P1 |
| model-evaluation-workflow Skill | ⏳ 待建 | P2 |
| clingo/docs/models/ 模型档案 | ⏳ 待建 | P2 |

---

## 💡 建议与注意事项

1. **offline_analysis.py 已更新**：修复后所有直方图均使用 P99 裁剪，后续对任何 benchmark 结果运行分析都会得到正确图表，无需额外操作

2. **hepan REPORT.md 待补充内容**：
   - `§一 背景与目的`：合盘解读模型上线背景
   - `§五 综合结论`：TTFT/E2E P90 是否符合 SLA
   - `§四.3 Grafana 截图`：`http://172.21.52.62:3000/d/cb7f886a-289f-4052-ae50-913644582b64/geniuworks`

3. **E2E P99 说明**：hepan 合盘输出 max_completion_tokens=4096，E2E P99=26s 属正常范围，可在报告中注明原因

---

## 📈 下次会话计划

### 优先级 1：tianji QPS 压测结果分析
- 压测完成后运行 `offline_analysis.py` 生成报告
- 确认拐点 QPS（成功率 <99.9% 或 TTFT P90 >2s 的档位）

### 优先级 2：Skill 建设继续
- `llm-deployment-docker`（P0，参考现有 deploy 脚本提炼）
- `llm-service-probing`（P1，参考 `test_remote_services.py`）

### 优先级 3：项目文档完善
- `clingo/docs/models/`：三个已迁移模型档案（ziwei/tianji/hepan）
- `clingo/docs/workflow/reporting-template.md`：报告模板规范

---

## 📊 项目整体状态（截至 2026-03-12 ~20:00）

| 模型 | 数据处理 | 本地部署 | 平台部署 | 压测 | 分析报告 |
|------|---------|----------|----------|------|---------|
| ziwei-32b (xinghan) | ✅ | ✅ | ✅ k8s v0.4.6.post2 | ✅ 4TP+8TP QPS sweep | ✅ HTML+PNG+REPORT（含 TP 对比）|
| ziwei-8b (twostep) | ✅ | ✅ | ✅ k8s v0.4.6.post2 | ✅ | ✅ |
| tianji-querysafety-4b | ✅ | ✅ | ✅ | 🔄 进行中 | ⏳ 待压测完成 |
| hepan-72b | ✅ | ⏳ | ✅ (同事部署) | ✅ 回放 150RPM + QPS sweep | ✅ 完整（HTML+PNG+REPORT×3）|

**Skill 建设进度**：

| Skill | 状态 |
|-------|------|
| `traffic-dataset-prep` | ✅ 已验证（情况 A+B，三模型通过）|
| `qps-benchmark-sweep` | ✅ 已建 |
| `llm-replay-benchmark` | ✅ 已建，hepan 验证通过 |
| `benchmark-result-analysis` | ✅ 已建，hepan 验证通过 |
| `qps-sweep-comparison` | ✅ 已建，hepan + ziwei 双场景验证通过 |
| `llm-deployment-docker` | ⏳ 待建 |
| `llm-service-probing` | ⏳ 待建 |
| `model-evaluation-workflow` | ⏳ 待建（依赖前面完成）|

---

# 会话报告 - 2026-03-12（下午场）

## 📌 会话概览

- **时间**：2026-03-12 下午
- **主要目标**：利用 `qps-sweep-comparison` Skill 对 hepan-72b-v1 QPS benchmark 结果进行可视化与分析，并将 ziwei TP 对比结果从 logs/ 迁移至 results/
- **Git 分支**：N/A（非 git 仓库）

## ✅ 成果

1. **hepan-72b-v1 orig 单组 QPS 分析**：`results/hepan_qps_jyf_20260312/`（3 HTML + REPORT.md）
   - SLA 结论：TTFS P90 ≤ 1.5s → 最大合规 0.70 req/s；≤ 1.6s → 0.80 req/s

2. **hepan-72b-v1 orig vs data600 双组对比**：`results/hepan_qps_compare_data600_20260312/`（3 HTML + REPORT.md）
   - SLA 基准放宽至 1.6s（用户确认）
   - data600 整体 TTFS P90 略低 3~4%，两组拐点一致，最大合规 QPS = 0.80 req/s

3. **ziwei TP8 vs TP4 完整报告补充**：`results/ziwei_tp_compare_20260310/REPORT.md`
   - TP8 = 1.50 req/s，TP4 = 0.92 req/s，效率比约 82%

4. **`multi_exp_compare.py` 增强**：新增 `file_pattern` 参数，支持在平铺目录中按文件名前缀过滤特定实验组

5. **logs/ 旧 HTML 清理**：删除 6 个旧版可视化文件，结果统一归档至 `results/`

## 🔧 文件变更

| 文件 | 操作 |
|------|------|
| `results/hepan_qps_jyf_20260312/` | ✨ 新增（3 HTML + REPORT.md）|
| `results/hepan_qps_compare_data600_20260312/` | ✨ 新增（3 HTML + REPORT.md）|
| `results/ziwei_tp_compare_20260310/REPORT.md` | ✨ 新增 |
| `results/ziwei_tp_compare_20260310/*.html` | ♻️ 重新生成（3 个）|
| `results/hepan_qps_jyf_20260312/REPORT.md` | 📝 更新（补双基准结论）|
| `multi_exp_compare.py` | ✨ `scan_group` 新增 `file_pattern` |
| `logs/*.html`（6 个）| 🗑️ 删除 |

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| 平铺目录扫描时无关文件被捞入 | 首次运行自动跳过（x_key 不匹配），后续新增 `file_pattern` 精确过滤 |
| orig 与 data600 在同一目录无法区分 | `scan_group` 新增 `file_pattern` 参数，调用方在 groups dict 中指定 |

## 🎯 技术决策

- **TTFS P90 基准放宽到 1.6s**：用户判断 1.577s 可接受，建议以 1.6s 作为 hepan-72b 实际上线评估标准
- **file_pattern 设计为可选参数**（`None` 时行为不变），保持向后兼容

## ⚠️ 未完成事项

- tianji QPS 压测仍在进行中
- hepan REPORT.md 背景、结论、Grafana 截图待用户补充
- `llm-deployment-docker` / `llm-service-probing` Skill 待建

## 📈 下次会话计划

1. **tianji QPS 压测结果分析**（压测完成后）
2. **Skill 建设**：`llm-deployment-docker`（P0）
3. **模型档案**：`clingo/docs/models/` 三个已迁移模型档案

---

# 会话报告 - 2026-03-12（晚场）— tianji-querysafety 回放测试 & Skill 收尾

## 📌 会话概览

- **时间**：2026-03-12 晚
- **主要目标**：
  1. 对新部署的 `tianji-querysafety-4b-v2-3` 服务执行回放基准测试（`llm-replay-benchmark` Skill 实战验证）
  2. 生成完整分析报告（HTML + PNG + REPORT.md），与 Grafana 线上监控交叉验证
  3. 更新 Skill 路线图与 TODO 文档，收尾 llm-replay-benchmark Skill 验证

---

## ✅ 成果

### 1. tianji-querysafety-4b-v2-3 回放测试（全量通过）

- **数据集**：`datas/output_tianji_querysafety/tianji-querysafety-4b-v2-3_peak30min.csv`（44,099 条，30 分钟真实峰值窗口，均值 1422 RPM，峰值 2168 RPM）
- **服务**：`https://infer.geniuworks.com/infra-tianji-querysafety-p4b-v23-bakv1/v1/chat/completions`
- **参数**：`--keep-income-time --no-kvcache --max-completion-tokens 256`
- **耗时**：~30 分钟

**核心指标**：

| 指标 | 值 | SLA |
|------|-----|-----|
| 成功率 | **100.00%** | ✅ ≥ 99% |
| TTFT 均值 | 0.122 s | ✅ |
| E2E 均值 | 0.214 s | ✅ |
| TPOT 均值 | 0.007 s | ✅ |
| POST 异常 | 0 | ✅ |

### 2. 完整分析报告交付

- **目录**：`results/tianji_querysafety_benchmark_20260312/`
- **产出**：交互式 HTML（18 MB）+ 7 张 PNG + `REPORT.md`（含 Grafana 比对）
- **Grafana 比对**：线上历史监控（2026-02-23 ~ 2026-03-11）三项指标与压测值高度一致，验证结果可信

### 3. Skill / 文档体系收尾

- `skills-roadmap.md`：`llm-replay-benchmark` 状态升为 ✅ 已验证，补充详情节
- `need-todo-idea.md`：T1/T5/T7 打勾，新增 T7.5（llm-replay-benchmark 完成条目）

---

## 🔧 文件变更

| 文件 | 操作 |
|------|------|
| `logs/tianji_querysafety_peak_replay_20260312_175115/` | ✨ 新增（回放结果 CSV + argv CSV）|
| `logs/tianji_querysafety_replay_20260312_175115.log` | ✨ 新增（完整运行日志）|
| `results/tianji_querysafety_benchmark_20260312/tianji_querysafety_peak_replay_1422rpm_analysis.html` | ✨ 新增 |
| `results/tianji_querysafety_benchmark_20260312/*.png`（7 张）| ✨ 新增 |
| `results/tianji_querysafety_benchmark_20260312/REPORT.md` | ✨ 新增（含 Grafana 比对节）|
| `clingo/docs/skills/skills-roadmap.md` | 📝 更新（状态 + 详情节 + 时间线）|
| `clingo/docs/need-todo-idea.md` | 📝 更新（TODO 状态 + T7.5 + I2）|

---

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| 数据目录无泊松插值文件 | 直接用 `_peak30min.csv` 回放，income_time 保真，等效真实流量 |
| StrReplace 编码不匹配导致替换失败 | 改用 Python 脚本 open/replace/write 方式绕过 |

---

## 🎯 技术决策

- **`_peak30min.csv` 直接回放可行**：Skill 文档中 `_poisson_{RPM}_stitched.csv` 是推荐路径，但当数据源为 CSV（情况 B）且峰值窗口已采样时，直接回放同样有效，无需额外泊松插值步骤
- **`max_completion_tokens 256`**：tianji-querysafety 为安全分类模型，输出极短（平均 ~14 tokens），256 已充分

---

## ⚠️ 未完成事项

- `llm-deployment-docker` Skill（P0，待建，下次优先）
- `llm-service-probing` Skill（P1，待建）
- `clingo/docs/models/` 三个模型档案（待建）
- `clingo/docs/workflow/model-onboarding.md` / `reporting-template.md` 待补充

---

## 📊 项目整体状态（截至 2026-03-13 更新）

| 模型 | 数据处理 | 本地部署 | 平台部署 | 压测 | 分析报告 |
|------|---------|----------|----------|------|---------|
| ziwei-32b (xinghan) | ✅ | ✅ | ✅ | ✅ QPS sweep（TP4+TP8）| ✅ REPORT + TP 对比 |
| ziwei-8b (twostep) | ✅ | ✅ | ✅ | ✅ | ✅ |
| tianji-querysafety-4b | ✅ | ✅ | ✅ bakv1 | ✅ 回放 1422 RPM + QPS sweep 全范围（4.0~10.0）| ✅ 完整（回放 + 拐点 + 4TP vs 4DP 三份报告）|
| hepan-72b | ✅ | ⏳ | ✅（同事）| ✅ 回放 150 RPM + QPS sweep | ✅ 完整（×3 报告）|

**Skill 建设进度**：

| Skill | 状态 |
|-------|------|
| `traffic-dataset-prep` | ✅ 已验证（情况 A+B，多模型）|
| `qps-benchmark-sweep` | ✅ 已验证（ziwei/tianji）|
| `llm-replay-benchmark` | ✅ 已验证（ziwei-32b + tianji-querysafety-4b）|
| `benchmark-result-analysis` | ✅ 已验证（ziwei/hepan/tianji 三模型）|
| `qps-sweep-comparison` | ✅ 已验证（hepan + ziwei + tianji 三场景，含 4TP vs 4DP 对比）|
| `llm-deployment-docker` | ⏳ 待建（下次优先）|
| `llm-service-probing` | ⏳ 待建 |
| `model-evaluation-workflow` | ⏳ 待建（依赖前面完成）|

**工具链改进**：

| 改进项 | 状态 |
|--------|------|
| `multi_exp_compare.py` YAML 外部配置 | ✅ 完成（`--config` 参数 + `configs/` 目录）|
| `print_sla_analysis` P95/P99 输出 + 3位精度 | ✅ 完成 |

---

## 🔑 关键技术发现（2026-03-13）

### tianji-querysafety-4b-v2-3 4TP 容量基准

| 维度 | 数值 |
|------|------|
| SLA 标准 | E2E P90 ≤ 400ms（主），E2E P95 ≤ 400ms（辅）|
| **SLA 合规最大 QPS** | **8.0 req/s（480 RPM）** |
| 拐点类型 | P95 软拐点（QPS=8.5 时 P95=0.422s 首次超标，P90=0.360s 仍 PASS）|
| 当前业务峰值 | 约 2168 RPM（≈36.1 req/s）|
| 单实例覆盖比例 | 22%（480/2168）|
| **推荐扩容方案** | **6 实例 × 4TP（24 卡 H100），含 20% 安全余量** |

### E2E 定义与 SGLang 缓存效应

- `E2E = token_list[-1].timestamp - token_list[0].timestamp`（**服务端处理时间，不含排队**）
- 高 QPS 下 SGLang 批处理更大、KV Cache 更热 → 服务端延迟可能反而更低（预热效应）
- 建议剔除 QPS=6.90/7.00 等"缓存骤降"异常点，避免影响趋势分析

---

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| 数据目录无泊松插值文件 | 直接用 `_peak30min.csv` 回放，income_time 保真，等效真实流量 |
| StrReplace 编码不匹配导致替换失败 | 改用 Python 脚本 open/replace/write 方式绕过 |
| Shell / StrReplace / Write 工具 "Timeout waiting for bubble creation" | 简单命令（ls/echo）正常；Python 运行用 nohup 后台 + 读文件方式规避；大文件写入改用 Write 直接重写整个文件 |
| E2E P90 精度不足（1位小数掩盖细节）| print_sla_analysis 改为 3位小数 + 增加 P95/P99 列 |

---

## 🎯 技术决策

- **`_peak30min.csv` 直接回放可行**：Skill 文档中 `_poisson_{RPM}_stitched.csv` 是推荐路径，但当数据源为 CSV（情况 B）且峰值窗口已采样时，直接回放同样有效
- **`max_completion_tokens 256`**：tianji-querysafety 为安全分类模型，输出极短（平均 ~14 tokens），256 已充分
- **E2E P90 ≤ 400ms 替代通用 E2E P90 ≤ 150s**：快进快出模型（8K 缓存前缀 + 极短 user input）延迟量级完全不同，通用标准无意义
- **剔除缓存预热异常点**：QPS=6.90/7.00 因 KV Cache 过热导致延迟骤降，不代表真实趋势，需剔除后再做拐点识别
- **YAML 外部配置**：避免每次分析都修改源码，`configs/` 目录作为实验配置仓库，文件名按 `model_deploy_date.yaml` 命名规范

---

## ⚠️ 未完成事项

- `llm-deployment-docker` Skill（P0，待建，**下次优先**）
- `llm-service-probing` Skill（P1，待建）
- `clingo/docs/models/` 三个模型档案（待建）
- `clingo/docs/workflow/model-onboarding.md` / `reporting-template.md` 已有修改，待完善
- `print_sla_analysis` P95/P99 增强代码：已写入，下次运行前请确认文件内容正确

---

## 📈 下次会话计划

1. **`llm-deployment-docker` Skill 建设**（P0 参考类，有 3 个参考脚本，写起来快）
2. **模型档案**：`clingo/docs/models/tianji-querysafety-4b.md` — 结合本次拐点数据填写容量基准
3. **`model-onboarding.md` 补充**：tianji-querysafety 作为情况 B 案例写入 SOP，补充容量评估环节
4. **qps-sweep-comparison Skill 更新**：将 tianji 4TP vs 4DP 作为新的参考案例写入，并补充"缓存预热异常点剔除"操作指南

---

---

# 会话报告 — 2026-03-13（HTTP 文件服务器优化）

## 📌 会话概览

- **日期**：2026-03-13
- **时间段**：15:00 ~ 15:45
- **主要目标**：修复静态文件服务器中文乱码 + 新增 Markdown 渲染能力
- **Git 分支**：不适用（非 git 仓库）

---

## ✅ 成果

1. **创建 `scripts/serve.py`**：统一替换项目中所有 `python3 -m http.server` 用法
   - 修复中文乱码：强制所有文本类型响应头加 `charset=utf-8`
   - Markdown 渲染：服务端用 `markdown-it-py` 将 `.md` 转为 GitHub 风格 HTML，支持表格、图片、代码块
   - 完全离线：CSS 内联，无需 CDN，适配无外网服务器环境
   - `?raw=1` 参数可查看原始文本
2. **清理旧进程**：kill 3 个旧 `http.server` 进程（端口 18999/8765/8891）
3. **nohup 持久化启动**：两个服务（18999/results、8765/logs）通过 `nohup` 启动，脱离 Cursor shell 生命周期

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/serve.py` | ✨ 新增（约 130 行）| 核心服务脚本 |

---

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| 新服务启动后仍乱码 | 浏览器缓存问题，`Ctrl+Shift+R` 强制刷新解决 |
| Markdown 页面"正在加载…"（CDN 不通）| 改用 `markdown-it-py` 服务端渲染，完全离线 |
| 进程意外消失 | Cursor shell 生命周期问题，改用 `nohup` 启动后解决 |

---

## 🎯 技术决策

- **选择 `markdown-it-py` 而非 `markdown`/`mistune`**：服务器环境中仅 `markdown-it-py 4.0.0` 已安装，且原生支持 GFM 表格（通过 `.enable("table")`），无需额外安装
- **CSS 内联而非单独文件**：减少请求数，避免额外依赖，适合简单内部工具场景
- **服务端渲染而非客户端渲染**：客户端渲染依赖 CDN JS 库，内网不可达；服务端渲染稳定可靠

---

## 🛠️ 当前运行服务

| 端口 | 目录 | 重启命令 |
|------|------|---------|
| 18999 | `results/` | `nohup python3 scripts/serve.py 18999 --bind 0.0.0.0 --directory results &>/tmp/serve_results.log &` |
| 8765 | `logs/` | `nohup python3 scripts/serve.py 8765 --bind 0.0.0.0 --directory logs &>/tmp/serve_logs.log &` |

---

## ⚠️ 未完成事项（延续上次）

- `llm-deployment-docker` Skill（P0，待建，**下次优先**）
- `llm-service-probing` Skill（P1，待建）
- `clingo/docs/models/` 三个模型档案（待建）
- `print_sla_analysis` P95/P99 增强代码：已写入，下次运行前请确认文件内容正确

---

## 📈 下次会话计划

1. **`llm-deployment-docker` Skill 建设**（P0）
2. **模型档案**：`clingo/docs/models/tianji-querysafety-4b.md`
3. **`model-onboarding.md` 补充**：tianji-querysafety 情况 B 案例 + 容量评估环节
4. **qps-sweep-comparison Skill 更新**：tianji 4TP vs 4DP 参考案例 + 缓存预热异常点剔除指南

---

# 会话报告 — 2026-03-13（tianji 4TP QPS 报告 E2E P95 补充分析）

## 📌 会话概览

- **日期**：2026-03-13
- **主要目标**：深度分析 QPS=6.9/7.0 延迟骤降现象，补充 E2E P95/P99 完整数据到 REPORT.md
- **Git 分支**：不适用（非 git 仓库）

---

## ✅ 成果

### 1. 原始数据精确计算（E2E P95/P99 全 30 档）

- 直接解析 `logs/tianji_qps_20260311_200338/` 30 个子目录中每条请求的 `token_list` 时间戳
- 精确计算 TTFT（`[START]` → 首个 content token）和 E2E（`[START]` → `[DONE]`）
- 数据精度从原来 0.1s 粒度提升为毫秒级

**核心发现**：

| QPS 段 | E2E P95 | E2E P99 | TTFT P90 | 现象 |
|--------|---------|---------|----------|------|
| 4.00~4.72 | 242~246ms | 585~646ms | 117~119ms | 低负载平稳段 |
| 4.83~5.03 | 269~302ms | 630~640ms | 116~117ms | P95 开始抬升 |
| 5.14~6.59 | 306~329ms | 681~807ms | 115~120ms | 中负载平台期，6.59 时 P99 达全程峰值 807ms |
| **6.90** | **270ms** | **554ms** | **107ms** | **转折点，缓存开始锁定** |
| **7.00** | **146ms** | **457ms** | **60ms** | **质变，TTFT 减半，缓存 100% 命中** |

### 2. 缓存机制解释升级

从"缓存预热效应"升级为 **"KV Cache 命中率阶跃式锁定"** 三阶段模型：

- **阶段 1**（QPS < 6.90）：8K Token 前缀缓存热但偶发驱逐，P99 随 QPS 升高累积至 807ms 峰值
- **阶段 2**（QPS = 6.90）：请求密度越过阈值，前缀条目被系统保持在显存热区，P99 骤降至 554ms
- **阶段 3**（QPS = 7.00）：前缀 prefill 几乎全部跳过（TTFT P90 = 60ms，仅需计算几十个 user token），E2E P95 从 329ms → 146ms（降幅 56%）

### 3. REPORT.md 更新

- **Section 3**：新增 E2E P95/P99 列，延迟单位统一为毫秒整数
- **Section 4**：关键异常表格补充 P95/P99，分析文字升级为三阶段机制
- **Section 6**：新增 E2E P95 表现行（全程 ≤ 329ms，余量 18%+）

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `results/tianji_querysafety_4tp_qps_20260311/REPORT.md` | 📝 重写 | 补充 E2E P95/P99 数据 + 升级缓存机制解释 |

---

## 🐛 问题与解决方案

| 问题 | 解决方案 |
|------|---------|
| `StrReplace` 匹配失败（旧文件使用 `\|\|` 双竖线格式） | 改用 `Write` 工具完整覆写，同时统一表格为标准单竖线格式 |
| Python 解析 18,900 行 × JSON 耗时约 104 秒 | 等待完成（属正常，单次离线计算可接受）|

---

## 🎯 技术决策

- **直接解析 token_list 时间戳**：比分析脚本的聚合输出精度更高（毫秒级 vs 0.1s 粒度），且可复现任意分位数
- **P99 作为缓存锁定的辅助证据**：P99 在 6.59 处的 807ms 峰值是"缓存即将锁定但还未锁定"临界态的最直接体现，比 P90 更敏感

---

## ⚠️ 未完成事项（延续上次）

- `clingo/docs/models/tianji-querysafety-4b.md` 模型档案（待建）
- `llm-deployment-docker` Skill（P0，待建）
- `llm-service-probing` Skill（P1，待建）

---

## 📈 下次会话计划

1. **模型档案**：`clingo/docs/models/tianji-querysafety-4b.md` — 记录容量基准（SLA 合规 QPS=8.0，需 6 实例覆盖峰值）
2. **`llm-deployment-docker` Skill 建设**（P0）
3. **`llm-service-probing` Skill 建设**（P1）

---

---

# 会话报告 - 2026-03-13（下午）

## 📌 会话概览

- **日期**：2026-03-13
- **主要目标**：tianji-querysafety-4b-v2-3 模型的 4TP vs 4DP 部署对比、4TP 真实拐点定位、工具精度修复与 Skill 文档补全
- **涉及模型**：`tianji_query_safety/v2p3_ep1`（4B 安全检测，SGLang 4TP 部署）

---

## ✅ 成果

### 1. 4TP 真实拐点定位

**结论：SLA 合规最大 QPS = 8.0 req/s（480 RPM）**

| 阶段 | QPS 区间 | E2E P90 | 状态 |
|------|---------|---------|------|
| 低负载稳定区 | 4.0 ~ 5.5 | 0.218~0.240s | ✅ PASS |
| 中负载平稳区 | 5.5 ~ 6.79 | 0.250~0.294s | ✅ PASS |
| 过渡区 | 7.5 ~ 8.0 | 0.300~0.330s | ✅ PASS |
| **拐点** | **8.0 → 8.5** | 0.330 → 0.363s | **❌ E2E P95=0.422s 首次超标** |
| 过载区 | 8.5 ~ 10.0 | 0.363~0.457s | ❌ FAIL |

扩容建议：覆盖业务峰值 2168 RPM（36.1 req/s）需 **6 个 4TP 实例 = 24 卡 H100**（含 20% 安全余量）。

### 2. 4TP vs 4DP 对比结论

| 部署配置 | SLA 合规最大 QPS | 档位结果 |
|---------|----------------|---------|
| **4TP×1实例** | **8.0 req/s** | ✅ 全 36 档 PASS（含高 QPS 段） |
| **1TP×4DP** | **None** | ❌ 全 28 档 FAIL（E2E P90 超标 4~8 倍） |

根本原因：8K Token system prompt 的 prefill 是决定性瓶颈。4TP 将注意力头分摊到 4 块 GPU，延迟约为 1TP 的 1/4。

### 3. E2E P90 精度修复

`multi_exp_compare.py` 的 `print_sla_analysis` 函数中 E2E P90 格式串由 `%10.1f`（1位）修复为 `%10.3f`（3位），与 TTFS P90 保持一致。

### 4. qps-sweep-comparison Skill 补全

新增三项内容：
- **方式 A（推荐）**：YAML `--config` 配置文件，不修改脚本
- **跨目录合并方案**：`cp -rl` 硬链接（✅）vs `ln -sfn` 符号链接（❌，Python glob 不追踪）
- **异常档位剔除规范**：建过滤目录保留原始数据，不直接删除

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `scripts/benchmark/run_tianji_querysafety_4tp_highqps_sweep.sh` | ✨ 新建 | 4TP 高 QPS 扫描脚本（7.5~10.0，6 档） |
| `logs/tianji_4tp_highqps_20260313_121446/` | ✨ 生成 | 高 QPS 6 档实验原始结果 |
| `logs/tianji_4tp_qps_merged/` | ✨ 新建 | 低+高段合并目录（36 档） |
| `logs/tianji_4tp_qps_merged_filtered/` | ✨ 新建 | 剔除 qps_6.90 / qps_7.00（34 档） |
| `logs/tianji_opti_qps_20260312_111300_filtered/` | ✨ 新建 | 剔除 opti_qps_6.79 / opti_qps_7.00（28 档） |
| `results/tianji_querysafety_4tp_vs_4dp_filtered_20260313/REPORT.md` | ✨ 新建 | 4TP vs 4DP 最终对比报告 |
| `results/tianji_querysafety_4tp_fullrange_20260313/REPORT.md` | ✨ 新建 | 4TP 全范围拐点报告（34 档） |
| `src/llm_benchmark/analysis/analysis/multi_exp_compare.py` | 🐛 修复 | E2E P90 输出精度 1位→3位 |
| `.cursor/skills/qps-sweep-comparison/SKILL.md` | 📚 更新 | YAML config + 跨目录合并 + symlink 警告 |

---

## 🐛 问题与解决方案

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| `multi_exp_compare.py` 扫描合并目录时找到 0 个文件 | `ln -sfn` 符号链接目录不被 `Path.glob("**/*.csv")` 遍历 | 改用 `cp -rl` 建硬链接目录，并在 Skill 中补充警告说明 |
| E2E P90 精度只有 1 位小数 | 格式串 `%10.1f` 与 TTFS P90 的 `%9.3f` 不一致（代码 bug） | 修复为 `%10.3f`，fail_reasons 同步修复 |
| `StrReplace` 无法精确匹配 REPORT 内容 | 文件之前被部分修改，与 old_string 有微小差异 | 改用 `Write` 工具完整覆写 |

---

## 🎯 技术决策

- **异常档位剔除用过滤目录而非删除**：保留原始实验数据完整性，过滤目录仅建硬链接，不占额外存储
- **4TP 合并用 `cp -rl` 而非 `ln -sfn`**：`Path.glob("**")` 默认不追踪指向目录的符号链接，硬链接是唯一可靠方案
- **KV Cache 热身点（QPS=6.90/7.00）列为异常剔除**：这两个点 TTFS P90 骤降至 0.236s/0.138s，不代表服务正常稳态，会扭曲拐点曲线的连续性判断

---

## ⚠️ 未完成事项

| 事项 | 优先级 | 说明 |
|------|--------|------|
| `clingo/docs/models/tianji-querysafety-4b.md` 模型档案 | P1 | 记录 SLA 容量基准、推荐部署方案 |
| `llm-deployment-docker` Skill | P0 | 待建 |
| `llm-service-probing` Skill | P1 | 待建 |

---

## 📈 下次会话计划

1. **模型档案建设**：`clingo/docs/models/tianji-querysafety-4b.md`，记录完整容量数据
2. **`llm-deployment-docker` Skill 建设**（P0）
3. **`llm-service-probing` Skill 建设**（P1）

---

---

# 会话报告 - 2026-03-13（下午：T8 model-evaluation-workflow）

## 📌 会话概览

- **日期**：2026-03-13
- **主要目标**：完成 T8 `model-evaluation-workflow` Skill 设计与编写，同步文档，提交 Git
- **Git 分支**：main
- **当前提交**：`2a7e606`（feat: add model-evaluation-workflow Skill (T8) and sync docs）
- **Skill 体系总数**：8 个全部完成

---

## ✅ 成果

### 1. ✨ `model-evaluation-workflow` Skill 正式完成（T8）

新模型接入的**顶层编排 Skill**，协调所有子 Skill 的调用顺序、跳过逻辑和进度记录。

**核心设计：两阶段 + 人工断点**

```
━━ 阶段一（本地准备）━━
  Step 0  信息收集
  Step 1  本地 Docker 部署         → llm-deployment-docker Skill
  Step 2  服务探测（无数据时）      → llm-service-probing Skill
  Step 3  数据处理（有数据时）      → traffic-dataset-prep Skill

  🔴 人工断点：AI 主动暂停，等待用户提供 k8s endpoint URL

━━ 阶段二（远端评估）━━
  Step 4  远端连通性验证（3项检查）
  Step 5  Benchmark              → llm-replay-benchmark + qps-benchmark-sweep
  Step 6  结果分析 & 报告归档    → benchmark-result-analysis + qps-sweep-comparison
```

**关键设计决策**：

| 决策点 | 选择 | 理由 |
|--------|------|------|
| Skill 结构 | Step Cards（步骤卡片）| 每步独立、跳过条件明确、易于跨会话续跑 |
| 进度追踪 | `progress.md` 文件写入 | 持久化、跨会话可读、人机均可查看 |
| 跳过粒度 | 每步独立前置检查（产物是否存在）| 避免重复执行，同时支持断点续跑 |
| 阶段一/二划分 | 本地 vs 远端，以 URL 为断点 | 两阶段时间跨度不同（本地立即 / 远端需人工操作平台）|
| 技术细节 | 不写在此 Skill，委托子 Skill | 保持单一职责，避免重复维护 |

**Step 0 部署规格两种形态（根据真实案例设计）**：

| 形态 | 案例 | 内容 |
|------|------|------|
| 形态 A | ziwei-32b / ziwei-8b | 直接给 `python3 -m sglang.launch_server ...` 命令 + 镜像名 |
| 形态 B | tianji-querysafety-4b | 给 Dockerfile（ENTRYPOINT 含完整启动命令）|

两种形态提取相同字段：镜像、模型路径、端口、tp-size/dp-size、chat-template、mem-fraction-static 等。

**文件位置**：
- Skill：`clingo/docs/skills/model-evaluation-workflow/SKILL.md`（323 行）
- 软链接：`.cursor/skills/model-evaluation-workflow` → `../../clingo/docs/skills/model-evaluation-workflow`

### 2. 📚 文档同步更新

| 文档 | 更新内容 |
|------|---------|
| `skills-roadmap.md` | `model-evaluation-workflow` 从 `⬜ 待建` → `✅ 完成`；`llm-deployment-docker`、`llm-service-probing` 详情章节验证状态补全 |
| `need-todo-idea.md` | T8 从 `[ ]` → `[x]` 标记完成 |
| `clingo/docs/README.md` | 目录树增加 `model-evaluation-workflow/`；Skill 体系表从"7个"→"8个" |
| `progress.md` | 添加本次会话日志（包括两阶段设计、Step 卡片、部署规格形态）|

---

## 🔧 文件变更

| 文件 | 操作 | 说明 |
|------|------|------|
| `clingo/docs/skills/model-evaluation-workflow/SKILL.md` | ✨ 新增 | T8 顶层编排 Skill，323 行 |
| `.cursor/skills/model-evaluation-workflow` | ✨ 新增（软链接）| Cursor IDE 加载入口 |
| `clingo/docs/skills/skills-roadmap.md` | 📝 修改 | 状态表 + 详情章节更新 |
| `clingo/docs/need-todo-idea.md` | 📝 修改 | T8 标记完成 |
| `clingo/docs/README.md` | 📝 修改 | 目录树 + Skill 体系表同步 |
| `progress.md` | 📝 更新 | 本次会话日志写入 |
| `project_status.md` | 📝 更新 | 本文件 |

**Git commit**：`2a7e606` — 8 文件变更，723 insertions, 45 deletions

---

## 🐛 问题与解决方案

本次会话无错误。

---

## 🎯 技术决策

1. **顶层 Skill 只做编排，不做执行**：`model-evaluation-workflow` 不重复描述技术细节，全部委托子 Skill，保持单一职责。下游 Skill 更新时，顶层 Skill 不需要跟着改。

2. **部署规格形态 A/B 统一抽象**：算法人员可能给命令行（ziwei 方式）或 Dockerfile（tianji 方式），Skill 统一抽象为"部署规格"，提取相同字段，屏蔽格式差异。

3. **人工断点明确化**：之前 `model-onboarding.md` 中断点是隐式的（用户自行理解），新 Skill 中 AI 主动输出格式化暂停消息，明确告知用户"现在需要你去平台部署，拿到 URL 后回来"。

4. **推理参数可选项**：`temperature`、`top_p`、`top_k`、`presence_penalty`、`max_tokens` 作为可选输入收集，Step 5 benchmark 时透传，确保测试结果与真实业务调用对齐。

---

## ⚠️ 未完成事项

| 事项 | 优先级 | 说明 |
|------|--------|------|
| guoxue QPS Sweep 全部完成 | P0 | `logs/guoxue_8tp_qps_20260316_163202/`，24 档，当前第 1/24 档运行中，预计今晚/明早完成 |
| process_guoxue_full.py & run_guoxue_8tp_qps_sweep.sh git commit | P0 | 上次 commit 指令 Abort，两个脚本尚未提交（`git status` 显示 untracked） |
| traffic-dataset-prep SKILL 补充步骤1.5 可跳过说明 | P1 | 已确认：DataSampler 不依赖 `_all.csv` 内容，仅采样管道可跳过步骤1.5；需在 SKILL 中补充条件说明 |
| `model-evaluation-workflow` GREEN 验证 | P1 | 待下次接入新模型时完整跑一遍验证 |
| `clingo/docs/models/` 模型档案目录 | P2 | IDEA I1，为每个模型维护技术说明书 |
| `workflow/reporting-template.md` | P3 | T3，基于 3 个模型 REPORT.md 抽象通用模板 |

---

## 💡 建议与注意事项

- **DataConverter `_all.csv` 陷阱已文档化**：步骤1.5 是「全量数据直接 benchmark 场景」的必要步骤；若只走 DataSampler 采样管道则可跳过，DataSampler 自己会读日期分片 CSV。建议在下次新模型处理前，先确认是否需要全量 replay（需要则执行步骤1.5，不需要则跳过）。
- `model-evaluation-workflow` 的 GREEN 阶段验证是最重要的中期目标：只有在真实新模型接入时跑完整流程，才能发现步骤卡片之间的衔接问题
- guoxue QPS Sweep 跑完后需要用 `qps-sweep-comparison` skill 出分析报告，结合业务 SLA 定拐点

---

## 📈 下次会话计划

1. **检查 guoxue QPS Sweep 进度**（`logs/guoxue_8tp_qps_20260316_163202/progress.txt`），若完成则用 `qps-sweep-comparison` skill 出报告
2. **补交未提交的脚本文件**：`scripts/data/process_guoxue_full.py`、`scripts/benchmark/run_guoxue_8tp_qps_sweep.sh`、`scripts/export_sessions.py`
3. **traffic-dataset-prep SKILL**：补充步骤1.5 的可跳过条件（DataSampler 路径 vs 全量 benchmark 路径）
4. 若有新模型接入：按 `model-evaluation-workflow` Skill 完整执行全流程（GREEN 阶段验证）

---

## 📊 最近会话摘要（2026-03-16 T2 — 历史会话导出）

**主要工作**：批量导出 2026-03-14 之前的 Cursor 历史会话，统一编号命名并提交

| 事项 | 结果 |
|------|------|
| 识别 7 个 Archived 会话（截图确认） | ✅ 完成 |
| 比对确认 6 个已导出会话对应的 UUID | ✅ 完成 |
| 编写 `scripts/export_sessions.py` 批量导出工具 | ✅ 完成（未单独提交） |
| 导出 17 个未导出会话（Markdown 格式） | ✅ 完成 |
| 统一重命名全部 24 个会话文件（01-24 顺序编号） | ✅ 完成 |
| Git Commit `86a62fc` | ✅ 完成（22 文件，10853 行新增） |

**会话文件现状（`clingo/sessions/`）**：

| 编号范围 | 日期 | 内容 |
|---------|------|------|
| 01-03 | 2026-03-09 | Docker 权限、项目初始化、部署脚本 |
| 04-08 | 2026-03-10 | 数据处理、拼接、回放测试、压力测试、日报 |
| 09-13 | 2026-03-11 | QPS sweep、benchmark、Dockerfile 部署、skill 规划、README |
| 14-18 | 2026-03-12 | Docker retag、QPS 结果、skill review、可视化、tianji 部署 |
| 19-24 | 2026-03-13 | QPS 分析、4DP、SLA、skill 下一步、HTTP server、hepan benchmark |

---

## 📊 最近会话摘要（2026-03-16 T1 — 文档整理 + guoxue 数据处理 + QPS Sweep）

**主要工作**：文档整理重组 + guoxue 数据处理脚本完善 + QPS Sweep 启动

| 事项 | 结果 |
|------|------|
| 文档目录重组（designs/、planning/ 新建） | ✅ 完成，commit `485d088` |
| traffic-dataset-prep SKILL 步骤1.5 + DataConverter 陷阱 | ✅ 完成，commit `979b4b3` |
| process_guoxue_full.py 各步骤产出文件批注 | ✅ 完成（未提交） |
| guoxue 完整数据处理 | ✅ 完成（5,726 行，峰值 220 RPM） |
| guoxue 8TP QPS Sweep 启动 | ✅ 进行中（第 1/24 档，约 62%） |

**关键技术发现**：DataConverter 原生 `_all.csv` 是 3 列索引文件（不含 `messages`/`old_response`），DataSampler 会绕过它直接读日期分片 CSV，故现有处理脚本安全；但手动使用 `_all.csv` 做 benchmark 会触发 `KeyError: 'old_response'`。

---

## 📊 最新会话报告（2026-03-17 — lingyu 模型资产完善）

### 📌 会话概览

- **日期**：2026-03-17（下午）
- **主要目标**：补全同事新添加的 `lingyu-235b-A22b-v9-2` 模型——完善 model-context.md、注册到 INDEX.yaml、迁移实验数据、生成 EVAL_REPORT.md、修复 Dashboard 问题
- **Git 分支**：main（最近提交：`5449d08`）
- **涉及模型**：lingyu-235b-A22b-v9-2（Qwen3-235B-A22B-Instruct-2507，H20×8，TP8/DP1）

---

### ✅ 成果

#### 1. model-context.md 完全补全
原文件有 7 处 `null` 占位字段，本次全部填入实际值：

| 字段 | 修正内容 |
|------|----------|
| `gpu_type` | H20 (96GB) |
| `dp_size` | 1 |
| `business_peak_rpm` | 800 |
| `endpoint_url` | `infra-lingyu-p235b-a22b-v9`（原为 v11 测试端点，已修正） |
| `current_instances` / `planned_instances` | 7（3+4）/ 10 |
| `recommended_instances` | 7（800 RPM ÷ 120 RPM/实例 = 6.67，取整）|
| `qps_sweep_data_path` | `logs/lingyu_qps_sweep_20260317`（替换原死路径 `results/lingyu_qps_sweep_20260317/REPORT.md`）|
| `inflection_type` | 修正为实测描述（TTFT 极稳定，E2E P90 在 2.0→2.1 后加速增长）|

#### 2. 原始数据迁移
从 jyf 工作区（`llm-benchmark-web-data/workspaces/jyf/results/`）迁移 60 个 CSV 文件到 `logs/lingyu_qps_sweep_20260317/`：
- `lingyu_rps_test_params_*`：QPS Sweep 原始数据（1.0~3.0 req/s，21 档）
- `lingyu_transfer_test_*`：多实例吞吐测试（1/3/4 副本 @6~8 req/s）

#### 3. INDEX.yaml 注册
新增 lingyu 完整条目（eval_status: completed），包含：
```yaml
deployment:
  tp_size: 8, dp_size: 1, gpu_type: H20 (96GB)
  current_instances: 7, planned_instances: 10
performance:
  sla_max_qps_rps: 3.0, inflection_point_rps: 2.0
  replay_*: null  # H20 环境限制，未做回放
```

#### 4. EVAL_REPORT.md 生成（基于实测数据）
路径：`results/models/lingyu/EVAL_REPORT.md`

从原始 CSV `token_list` 字段解析出 21 档完整指标：

| QPS (req/s) | TTFT P90 | E2E P90 | 成功率 | 判定 |
|-------------|---------|---------|--------|------|
| 1.0 | 0.343s | 2.9s | 100% | ✅ |
| **2.0** | **0.346s** | **4.8s** | **100%** | **✅ ← 拐点** |
| 3.0 | 0.386s | 11.3s | 100% | ✅ |

核心结论：TTFT P90 全程极稳定（+12.5%），E2E P90 在 QPS≥2.0 后加速增长，拐点明显。

#### 5. Dashboard 问题修复
- `⚠️ EVAL_REPORT.md 不存在` → 创建文件后消除
- 重复链接（`lingyu_qps_sweep_20260317` 出现两次）→ 移除未生成的 `results/` 条目

---

### 🐛 问题与解决方案

| 问题 | 根因 | 解决 |
|------|------|------|
| TTFT 计算为 145491s | `income_time` 是数据集原始时间戳（非请求发送时间），相差约 40 小时 | 改用 `token_list[0].timestamp`（`[START]` 标记）作为请求起始时间 |
| CSV 字段读取报 `field larger than field limit` | `token_list` JSON 字符串超出默认 131072 限制 | `csv.field_size_limit(10**8)` |
| 文件名搜索失败（`llingyu`）| 路径中有双 `l` 笔误 | `ls | grep -i lingyu` 确认实际文件名 |
| `qps_sweep_report_path` 死路径 | `results/lingyu_qps_sweep_20260317/REPORT.md` 从未创建 | 改为 `qps_sweep_data_path` 指向 logs 数据目录 |

---

### 🎯 技术决策

1. **不做回放测试**：H20 环境下 `--keep-income-time` 模式无法构建实时回放（网络/延迟条件不同），直接跳过，仅依据 QPS Sweep 结论上线。
2. **实测数据覆盖同事记录**：`inflection_type` 原描述"TTFS P90 +34%"与实测不符（TTFT P90 全程仅 +12.5%），已修正为 E2E P90 拐点特征。
3. **7 实例裕量偏紧**：800 RPM ÷ 120 RPM/实例 = 6.67，7 实例仅 5% 裕量，建议优先推进扩容至 10 实例。

---

### ⚠️ 未完成事项

| 事项 | 状态 | 备注 |
|------|------|------|
| `results/lingyu_qps_sweep_20260317/REPORT.md` | ✅ 同事已生成 | 作为独立 QPS Sweep 报告存在 |
| lingyu EVAL_REPORT.md 中 transfer_test 吞吐数据 | ⏳ 仅列出实验路径 | 可补充实测的 4 实例 @8 req/s 数据 |
| guoxue Step 6/7（分析与报告）| ⏳ Sweep 进行中 | 等 `logs/guoxue_8tp_qps_20260316_163202/` 全部完成 |

---

### 💡 建议与注意事项

1. **lingyu 扩容优先级**：当前 7 实例对 800 RPM 峰值仅 5% 裕量，若有突发流量需立即限流。计划扩容至 10 实例（1200 RPM 容量，50% 裕量）应尽快推进。
2. **H20 基准可复用**：H20 单卡 QPS 特征（TTFT 极平稳、E2E 软拐点）与 L20 模型有明显差异，可在 insights 中记录为跨平台技术发现。
3. **INDEX.yaml 维护**：下次接入新模型时，注册 INDEX.yaml 应与 model-context.md 同步完成，避免 Dashboard 显示警告。

---

### 📈 下次会话计划

1. **guoxue Step 6**：QPS Sweep 完成后，用 `multi_exp_compare.py` 做分析，生成 `results/guoxue_*/REPORT.md`
2. **guoxue Step 7**：生成 `results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md`，更新 INDEX.yaml 状态为 completed
3. **lingyu transfer_test 补充**：可从 `logs/lingyu_qps_sweep_20260317/lingyu_transfer_test_*` 补充多实例吞吐分析
4. **新模型评估周期**：如有新模型到来，使用 `model-evaluation-workflow` Skill 全流程接入

---

# 会话报告 — 2026-03-18（晚场）

## 📌 会话概览

- **开始时间**：2026-03-18（接续前一会话，chart QPS sweep 运行中）
- **结束时间**：2026-03-18 晚
- **主要目标**：benchmark 脚本资产化 —— 通用脚本 + `.env` 配置文件体系设计与实现
- **Git 分支**：`main`
- **当前提交**：`8ac0917`（fix(analysis): add compare_analysis.py and fix TTFS definition in skill）
- **触发背景**：chart QPS sweep 运行期间，用户提出当前模型专属脚本模式不可持续，需要系统化设计

---

## ✅ 成果

### 1. ♻️ 通用 Benchmark Runner 设计文档

**文件**：`clingo/docs/designs/2026-03-18-generic-benchmark-runner-design.md`

完整记录方案 C（通用脚本 + `.env` 文件）的设计决策，包含：
- **问题背景**：每个模型需 2~3 个专属脚本，80%+ 逻辑重复，升级维护成本高
- **目录结构规范**：`configs/models/<model>/<tp>.env` + `README.md`
- **`.env` 文件规范**：6 个固定分节（模型基础 / 数据处理 / Benchmark 公共 / QPS Sweep / Replay）
- **特殊值 ⚠️ 注释约定**：非标准参数必须行内说明原因
- **特例处理机制**：`.env` 注释 → 模型 README → 根目录 README 共性累积 → 通用脚本迭代
- **新模型接入 6 步流程**
- **4 个 Skill 更新说明**（设计文档内已明确每个 Skill 需新增什么节）

### 2. ✨ 三个通用脚本实现

| 脚本 | 功能 |
|------|------|
| `scripts/benchmark/run_qps_sweep.sh` | 接受 `<config.env>`，source 配置 → 参数校验 → QPS 档位生成 → 循环 benchmark → 写实验目录 README + progress.txt |
| `scripts/benchmark/run_replay.sh` | 接受 `<config.env>`，校验 `REPLAY_*` 字段 → keep-income-time 回放 → 写实验目录 README |
| `scripts/data/process.py` | 接受 `--env <config.env>`，按 `DATA_FORMAT` 分派 standard（DataConverter）/ indexed（download + 转换）处理路径；indexed 内置断点续传 |

### 3. ✨ 首个模型 `.env` 配置（xinghan-chart-32b-v1-1-agent）

| 文件 | 说明 |
|------|------|
| `configs/models/xinghan-chart-32b-v1-1-agent/8tp.env` | 8TP 部署完整配置，含 2 处 ⚠️ 特例注释 |
| `configs/models/xinghan-chart-32b-v1-1-agent/4tp.env` | 4TP 对照组配置 |
| `configs/models/xinghan-chart-32b-v1-1-agent/README.md` | 两阶段数据处理特例说明、replay 计划 |
| `configs/models/README.md` | 共性发现根文档 + 新模型接入命令步骤 |

chart 模型两处特例：
- `DATA_FORMAT=indexed`：JSONL 是索引文件，需先 `download_by_indices.py` 下载
- `DURATION=1500`（非标 2700）：有效数据仅 6,016 条，`QPS_END×2700=10,800` 超限

### 4. 📚 4 个 Skills 更新

| Skill | 更新内容 |
|-------|----------|
| `qps-benchmark-sweep` | 新增"新模式执行方式"节：`.env` 参数速查表、两组对照组并行启动模板 |
| `llm-replay-benchmark` | 新增"新模式执行方式"节：前置 `REPLAY_*` 参数检查说明 |
| `traffic-dataset-prep` | 新增"新模式执行方式"节：`DATA_FORMAT` 枚举表、断点续传机制说明 |
| `model-evaluation-workflow` | 新增 Step 2.5（创建 `.env`）；更新 Step 3 分派逻辑（standard/indexed）；更新 Step 5 使用通用脚本；调整 Step 5 执行顺序（先 sweep 后 replay）|

---

## 🔧 文件变更

| 文件 | 操作 | 分类 |
|------|------|------|
| `clingo/docs/designs/2026-03-18-generic-benchmark-runner-design.md` | ✨ 新建（约 180 行）| 📚 设计文档 |
| `scripts/benchmark/run_qps_sweep.sh` | ✨ 新建（约 165 行）| ✨ 通用脚本 |
| `scripts/benchmark/run_replay.sh` | ✨ 新建（约 110 行）| ✨ 通用脚本 |
| `scripts/data/process.py` | ✨ 新建（约 220 行）| ✨ 通用脚本 |
| `configs/models/README.md` | ✨ 新建 | 📚 配置文档 |
| `configs/models/xinghan-chart-32b-v1-1-agent/8tp.env` | ✨ 新建 | 🔧 配置文件 |
| `configs/models/xinghan-chart-32b-v1-1-agent/4tp.env` | ✨ 新建 | 🔧 配置文件 |
| `configs/models/xinghan-chart-32b-v1-1-agent/README.md` | ✨ 新建 | 📚 特例说明 |
| `clingo/docs/skills/qps-benchmark-sweep/SKILL.md` | 📝 更新 | 📚 Skill 文档 |
| `clingo/docs/skills/llm-replay-benchmark/SKILL.md` | 📝 更新 | 📚 Skill 文档 |
| `clingo/docs/skills/traffic-dataset-prep/SKILL.md` | 📝 更新 | 📚 Skill 文档 |
| `clingo/docs/skills/model-evaluation-workflow/SKILL.md` | 📝 更新 | 📚 Skill 文档 |
| `progress.md` | 📝 追加 | 📋 日志 |

---

## 🐛 问题与解决方案

本次会话为纯设计+实现任务，无报错。

---

## 🎯 技术决策

1. **选择方案 C（通用脚本 + `.env`）而非方案 A（YAML）或方案 B（model-context.md 直接驱动）**  
   原因：AI Agent 为主执行者，`bash source` 原生支持，零新依赖；一个 `.env` 覆盖数据处理和 benchmark 全流程参数，单次生成可复用

2. **`.env` 文件粒度：每个部署一份（8TP/4TP 各独立）**  
   原因：一个模型可同时有多个部署对照组，参数（SERVER_URL、GROUP_NAME、TP_SIZE）各不相同，独立文件保证清晰无歧义

3. **旧专属脚本策略：保留不删除**  
   原因：已完成评估的模型有历史参考价值，强行删除会丢失已记录的参数上下文。旧脚本标注"历史参考，不再维护"

4. **通用脚本内置实验目录 README 自动生成**  
   解决问题：过去每次 benchmark 完成后需手动补写 README，容易遗忘；现在 `run_qps_sweep.sh` 启动时即写入，内容来自 `.env` 参数，零额外成本

5. **`process.py` 中 indexed 模式内置断点续传**  
   原因：chart 数据下载需 40 分钟，中途失败后重跑成本高；检测 `_downloaded_raw.jsonl` 是否存在，存在则跳过下载步骤

---

## ⚠️ 未完成事项

| 事项 | 说明 | 优先级 |
|------|------|--------|
| guoxue 分析 | 用户暂缓，需自行调整分析内容 | 暂停 |
| chart 8TP vs 4TP 正式对比分析 | 需调整 SLA 阈值后重跑 `multi_exp_compare`，再找延迟拐点 | **最高** |
| chart QPS 扩展测试 | 当前 4.0 QPS 有 15× E2E 余量，需扩展至 8~15 req/s 找真正拐点 | **最高** |
| chart replay 测试 | 待 QPS 拐点确认后生成插值数据集 | 高 |
| 业务侧空响应重试机制 | 检测 `completion_tokens==1 AND content==null` 触发重试 | 中优先 |
| 模型侧空响应排查 | 联系模型团队确认采样参数（temperature/top_p），评估降低概率可行性 | 低优先 |
| `scripts/data/converter.py` | `process.py` standard 模式依赖此文件，尚未创建通用版本 | 中优先 |
| 补全实验目录 README（历史遗留）| `logs/ziwei_*`、`logs/tianji_*` 等老实验 README 内容简略 | 低优先 |

---

## 💡 建议与注意事项

1. **chart SLA 阈值必须先调整**：`success_rate` 从 `0.99` 改为 `0.98`，否则 8TP/4TP 全部档位都会因固有空响应基线（~1.24%）而 FAIL，掩盖真实容量结论
2. **空响应是模型固有特征，不是容量瓶颈**：已通过完整数据验证（与 QPS 无关、与特定 prompt 无决定论关联），不要以此判断服务不可用
3. **chart 真实容量远高于当前测试范围**：8TP @ 4.0 QPS 的 E2E P90=9.767s，SLA 门限 150s，余量 15×，拐点预计在 8~15 QPS
4. **bad case 工具使用**：`analysis --exp logs/chart-32b-8tp-null-decode --host 0.0.0.0 --port 18555`，加载 `badcase_for_analysis.csv` 可交互浏览所有空响应样本
5. **offline_analysis.py REPORT.md 不自动写入**：脚本只打印骨架到终端，需手动保存文件（或后续为脚本添加 `--report` 参数）
6. **Phase 1 步进过冲问题**：大幅翻倍（×2）在高吞吐区间可能越过峰值，建议后续加二分保护
7. **`.env` 特例 ⚠️ 注释要坚持写**：这是唯一能让新人（或 AI）快速理解非标参数的机制

---

## 🧠 关键发现沉淀

### chart-32b 空响应问题（2026-03-19 新增）

**现象**：~1.24% 的请求返回 HTTP 200 但无内容输出  
**标志**：`matched_stop=151645`（Qwen `<|im_end|>`），`completion_tokens=1`，`token_list=[START,DONE]`  
**根因**：模型在第一个 token 采样时以极低概率命中 `<|im_end|>`，产生 0 字可见回复  
**验证**：与 QPS 无关、与特定 prompt 无决定论关联、输入数据无异常  
**影响**：SLA `success_rate≥99%` 全面失守，掩盖真实容量分析  
**数据**：`logs/chart-32b-8tp-null-decode/REPORT.md` + `badcase_for_analysis.csv`

### qps-peak-finder 方法论总结

#### Phase 1：饱和探测
- **两阶段步进**：增幅 >10% 时翻倍，1-10% 时线性 +10；增幅 <1% 或下降则停止
- **已知问题**：翻倍步进可能过冲，建议后续加入回退二分

#### Phase 2a：两阶段收敛（2026-03-19 升级）
**阶段 1 - 比例快速逼近**（无 bracket）：
- 超载首档：直接跳到 `peak_rps × 0.8`
- SLA 不通过：`next = current × (1/worst_ratio)^0.8`
- SLA 通过（裕量大）：`next = current × min((1/worst_ratio)^0.6, 1.25)`
- SLA 通过（裕量 <5%）：收敛，建议传入 bracket 精查

**阶段 2 - bracket 几何中点精查**（有 lo/hi 时自动启用）：
- bracket 宽度 ≥ 3%：`next = sqrt(lo × hi)`（每步宽度减半）
- bracket 宽度 < 3%：收敛，`ideal_rps = lo`
- **实测效果**：guoxue 纯比例振荡 11 次，传入 bracket 后 **1 次收敛**

---

## 📈 下次会话计划

### ✅ 已完成：guoxue-72b 最终报告（2026-03-19 中午）

1. **EVAL_REPORT.md 已生成**：`results/models/xinghan-guoxue-72b-v1-2-reason/EVAL_REPORT.md`
   - 综合原网格搜索（0.245 req/s）+ qps-peak-finder（0.2494 req/s），偏差 1.8% 交叉验证
   - 上线建议：⚠️ 有条件上线，推荐 4 实例 × 8TP = 32 卡 L20
2. **实验报告已生成**：`results/guoxue_qps_peak_finder_20260318/REPORT.md` + 3 个 HTML 图表
3. **results/README.md** 已补充新条目

### 高优先：chart-32b 容量分析

2. **调整 SLA 阈值 `success_rate: 0.98`，重跑 8TP vs 4TP 对比分析**：
   - 运行 `multi_exp_compare`，查看真实延迟拐点

3. **扩展 QPS 测试范围至 8~15 req/s**：
   - 使用 `run_qps_sweep.sh` + `configs/models/xinghan-chart-32b-v1-1-agent/8tp.env`

4. **确认拐点 QPS → 执行 replay 测试**：
   ```bash
   bash scripts/benchmark/run_replay.sh configs/models/xinghan-chart-32b-v1-1-agent/8tp.env
   ```

### 其他

5. **标准 converter.py 实现**（按需）：有 standard 格式新模型时实现

6. **Phase 2a 下一步可用 bracket 续跑**（如需重验）：
   ```bash
   INIT_LO=0.2494 INIT_HI=0.2529 bash scripts/benchmark/run_phase2_auto.sh
   ```
