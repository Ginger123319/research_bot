# Benchmark 报告写作模板

> 更新：2026-03-17  
> 适用范围：`results/<exp_dir>/REPORT.md` 实验级报告

本文件包含两种报告类型的写作模板，以及通用写作规范。

---

## 报告类型选择

| 情况 | 使用模板 |
|------|---------|
| 用真实业务数据集回放，验证服务稳定性 | **模板 A：回放压测报告** |
| 多档 QPS 施压，找拐点或对比部署方案 | **模板 B：QPS 拐点 / 对比报告** |

---

## 通用写作规范

### 必填字段规则

- 延迟分位数（P50 / P90 / P95 / P99）**必须填写具体数值**，禁止写"见图"、"见 HTML"
- 结论表的每一行**必须有判断标准和实测值**，禁止留空或写"<填写>"
- 原始数据摘要（`§六.2`）**必须包含**，直接复制 benchmark 工具输出即可
- 上线建议**必须给出明确结论**（✅ 可上线 / ⚠️ 有条件 / ❌ 暂不建议）

### 数字格式规范

| 字段 | 格式 | 示例 |
|------|------|------|
| 延迟（秒） | 保留 3 位小数 | `1.002 s` |
| 成功率 | 百分比 + 小数点后 2 位 | `99.97%` |
| QPS（req/s） | 保留 3 位小数 | `0.846 req/s` |
| RPM | 整数 | `100 RPM` |
| Token 数 | 整数 + 逗号分隔 | `3,036 条` |

### 图表引用规范

图片文件统一放在实验目录下，引用时使用相对路径：
```markdown
![TTFT CDF](ttft_cdf.png)
![Grafana 监控](xinghan-{model}_grafana_peak_{date}.png)
```

---

## 模板 A：回放压测报告

> 适用：`llm-replay-benchmark` Skill 执行后生成

```markdown
# {model_name} 性能验证报告

> **测试时间**：YYYY-MM-DD  
> **测试目标服务**：{endpoint_url}  
> **结论**：✅/⚠️/❌ {一句话结论，含成功率、关键延迟指标、是否满足上线条件}

---

## 一、背景与目的

### 1.1 迁移/上线背景

{说明本次测试的背景：为什么需要测试、服务迁移的上下游关系、与旧服务的对应关系}

- **原服务标识**：{旧 endpoint 或 N/A}
- **新服务标识**：{新 endpoint 标识}

### 1.2 测试目标

通过真实生产流量回放，在不低于历史线上峰值的压力条件下，验证：

1. 新服务**可用性**（成功率）是否满足生产标准（≥ 99%）
2. 关键延迟指标（TTFT / E2E）是否在 SLA 门限内
3. 高并发/高峰值场景下服务是否保持稳定

---

## 二、测试方法论

### 2.1 测试数据构建流程

```
原始生产日志 (JSONL)          {行数} 行，{日期范围}
         │
         ▼
 [步骤1] 完整数据转换          model_list: "{model_name},{中文别名}"（{N} 条）
         │
         ▼
 [步骤2] 峰值窗口采样          {N} 天峰值时段各 ±{M} 分钟，共 {K} 条
                              ┌ {date1} {time1}~{time2}（{n1} 条，峰值 {r1} RPM）
                              └ {date2} {time1}~{time2}（{n2} 条，峰值 {r2} RPM）
         │
         ▼
 [步骤3] 泊松过程流量插值       峰值从 {src_rpm} RPM 放大至 {dst_rpm} RPM（+{pct}%）
                              {src_cnt} 条 → {dst_cnt} 条
         │
         ▼
 [步骤4] 拼接为连续 {T} 分钟    段间大间隔归零，保留突发形态
         │
         ▼
 ★ 最终压测数据集              {dataset_filename}
                              {total_cnt} 条，峰值 {dst_rpm} RPM
```

### 2.2 压测执行参数

| 参数 | 值 |
|------|-----|
| 数据集 | `{dataset_path}`（{total_cnt} 条）|
| 请求模式 | `--keep-income-time`（按真实到达时间回放）|
| KV Cache | `--no-kvcache`（禁用缓存命中）|
| max_completion_tokens | {N}（{对话类 4096 / 短输出 256}）|
| 随机前缀注入 | ✅ UUID 前缀（`--no-kvcache` 自动启用）|
| tokenizer | `{tokenizer_path}` |
| 测试端点 | `{endpoint_url}` |

### 2.3 与线上峰值的对应关系

| 来源 | 峰值 RPM | 依据 |
|------|----------|------|
| 原始日志实测 | {src_rpm} RPM | JSONL 数据分析 |
| 日监控（Grafana） | {grafana_rpm} RPM | {日期} 历史最高峰 |
| **本次压测峰值** | **{dst_rpm} RPM** ✅ | 对齐/超越 Grafana 监控峰值 |

---

## 三、测试结果汇总

### 3.1 可用性指标

| 指标 | 值 |
|------|-----|
| 总请求数 | {all_cnt} |
| **成功请求数** | **{success_count}** |
| **成功率** | **{success_rate}%** ✅/❌ |
| 失败请求数 | {fail_count} |
| POST 异常数 | {post_error_count} |
| 流解析异常数 | {stream_error_count} |
| 测试总耗时 | {total_duration} s（≈ {T} 分钟）|
| 实测 QPS | {success_qps} req/s（≈ {rpm_mean} RPM 均值，峰值 {dst_rpm} RPM）|

### 3.2 延迟分布（CDF 分位数）

#### TTFT（首 Token 时间）

| 分位数 | 值 |
|--------|----|
| Mean   | **{ttft_mean} s** |
| P50    | {ttft_p50} s |
| P90    | **{ttft_p90} s** |
| P95    | {ttft_p95} s |
| P99    | {ttft_p99} s |
| P100 (Max) | {ttft_max} s |

![TTFT CDF](ttft_cdf.png)

#### TTFS（首句响应时间）

| 分位数 | 值 |
|--------|----|
| Mean   | **{ttfs_mean} s** |
| P50    | {ttfs_p50} s |
| P90    | **{ttfs_p90} s** |
| P95    | {ttfs_p95} s |
| P99    | {ttfs_p99} s |

![TTFS CDF](ttfs_cdf.png)

#### E2E（端到端总响应时间）

| 分位数 | 值 |
|--------|----|
| Mean   | **{e2e_mean} s** |
| P50    | {e2e_p50} s |
| P90    | **{e2e_p90} s** |
| P95    | {e2e_p95} s |
| P99    | {e2e_p99} s |
| P100 (Max) | {e2e_max} s |

> ⚠️/✅ {P99/Max 异常或正常的解释，如"长输出场景正常"或"无异常"}

![E2E CDF](e2e_cdf.png)

#### TPOT / ITL（逐 Token 生成时间）

| 分位数 | 值 |
|--------|----|
| Mean (User-TPOT) | **{tpot_mean} s** |
| P50    | {tpot_p50} s |
| P90    | {tpot_p90} s |
| P99    | {tpot_p99} s |

![ITL CDF](itl_cdf.png)

### 3.3 吞吐量指标

| 指标 | 值 |
|------|-----|
| Prefill 吞吐量 | **{prefill_throughput} tokens/s** |
| Decode 吞吐量 | **{decode_throughput} tokens/s** |
| 综合吞吐量 | **{overall_throughput} tokens/s** |
| 平均 Prefill 长度 | {avg_prefill} tokens |
| 平均输出 tokens | {avg_output} tokens |

### 3.4 并发与成功率时间线

![并发 Timeline](concurrency_timeline.png)
![成功率 Timeline](success_rate_timeline.png)

<!-- 可选节：对话类模型需要功能输出质量验证时使用 -->
<!--
### 3.5 功能输出质量验证

{对单次真实业务 prompt 的功能测试结论，验证模型输出格式和内容质量}

![功能测试输出样例](functional_test_results.png)
-->

---

## 四、有效性论证

### 4.1 测试数据真实性

| 维度 | 说明 |
|------|------|
| **数据来源** | 生产环境实际请求日志（非合成数据），保留真实 system prompt 和对话上下文 |
| **别名覆盖** | 同时使用 `{model_name}` + `{chinese_alias}` 过滤，覆盖全部业务数据 |
| **分布代表性** | 采样自 {N} 天独立峰值时段，避免单一时段偶然性 |
| **输入长度分布** | Prefill 均值 {avg_prefill} tokens，{说明长上下文分布} |

### 4.2 流量压力充分性

| 指标 | 值 |
|------|-----|
| 原始数据流量峰值 | {src_rpm} RPM（日志实测）|
| 泊松插值后峰值 | **{dst_rpm} RPM**（约 {multiplier}x 放大）|
| 放大倍数 | {multiplier}x（{src_cnt} 条 → {dst_cnt} 条）|

![泊松插值前后流量对比](benchmark-data-poisson_{dst_rpm}_compare.png)

### 4.3 与 Grafana 线上监控的横向比对

![Grafana 线上峰值监控]({model_name}_grafana_peak_{date}.png)

| 指标 | 本次测试（直连推理）| Grafana 线上（MCP 应用层）|
|------|-----------------|--------------------------|
| 成功率 | **{success_rate}%** | {grafana_success_rate}（{说明}）|
| 首句延迟均值 | **{ttfs_mean} s**（TTFS）| **{grafana_ttfs} s**（MCP 首句，含应用层开销）|
| 整体响应时长均值 | **{e2e_mean} s**（E2E）| **{grafana_e2e} s**（MCP 整体）|
| 峰值 RPM | {dst_rpm}（压测设定）| **{grafana_peak_rpm}**（历史线上峰值）|

> **说明**：Grafana 展示应用层（MCP）指标，与 benchmark 直连推理指标存在正常差距（应用层额外开销）。两者趋势吻合，差值符合预期。

### 4.4 P99/Max 延迟的合理解释

{解释 P99 和 Max 偏高的原因，例如：长输出场景、禁用 KV Cache 条件下的正常现象}

<!-- 可选：有多轮测试时填写 -->
<!--
### 4.5 多轮测试一致性

| 测试轮次 | 数据集（峰值）| 成功率 | TTFT P90 | E2E P90 |
|----------|--------------|--------|----------|---------|
| 测试一 | {description} | {n}% | {x} s | {x} s |
| 测试二 | {description} | {n}% | {x} s | {x} s |
-->

---

## 五、结论与上线建议

### 5.1 综合结论

| 验证项 | SLA 标准 | 实测值 | 结论 |
|--------|---------|--------|------|
| 可用性（成功率）| ≥ 99% | **{success_rate}%** | ✅/❌ |
| TTFT P90 | ≤ {sla_ttft}s | **{ttft_p90} s** | ✅/❌ |
| TTFS P90 | ≤ {sla_ttfs}s | **{ttfs_p90} s** | ✅/❌ |
| E2E P90 | ≤ {sla_e2e}s | **{e2e_p90} s** | ✅/❌ |
| 峰值压力覆盖 | ≥ {target_rpm} RPM | **{dst_rpm} RPM** | ✅/❌ |
| POST 异常 | 0 | **{post_error_count}** | ✅/❌ |

### 5.2 上线建议

**结论**：✅ 可上线 / ⚠️ 有条件上线 / ❌ 暂不建议上线

{2-4 条具体建议，包含：
1. 是否可上线及理由
2. 上线时的注意事项或监控重点
3. 可选：灰度发布建议
4. 可选：超长请求/边缘情况处理建议}

---

## 六、附录

### 6.1 文件清单

| 文件 | 说明 |
|------|------|
| `{exp_name}_analysis.html` | 交互式完整分析报告 |
| `ttft_cdf.png` | TTFT 累积分布曲线 |
| `ttfs_cdf.png` | TTFS 累积分布曲线 |
| `e2e_cdf.png` | E2E 累积分布曲线 |
| `itl_cdf.png` | ITL / TPOT 累积分布曲线 |
| `concurrency_timeline.png` | 并发数时间线 |
| `success_rate_timeline.png` | 成功率时间线 |
| `benchmark-data-poisson_{N}_compare.png` | 泊松插值前后流量对比图 |
| `{model_name}_grafana_peak_{date}.png` | Grafana 线上监控截图 |

### 6.2 原始数据摘要

```
total_duration:      {x} s
all_cnt:             {x}
success_count:       {x}
success_rate:        {x} ({x}%)
success_qps:         {x} req/s
ttft_mean:           {x} s
ttfs_mean:           {x} s
tpot_mean:           {x} s
user_tpot_mean:      {x} s
e2e_mean:            {x} s
prefill_throughput:  {x} tokens/s
decode_throughput:   {x} tokens/s
overall_throughput:  {x} tokens/s
```

### 6.3 测试执行命令

```bash
nohup benchmark \
  --exp-name {exp_name} \
  --dataset-path {dataset_path} \
  --url {endpoint_url} \
  --tokenizer {tokenizer_path} \
  --model ignore-model-name \
  --no-kvcache \
  --keep-income-time \
  --max-completion-tokens {N} \
  --output-dir logs/{exp_dir} \
  > logs/data-pipeline/{exp_name}_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```

---

*报告生成时间：{YYYY-MM-DD}*  
*数据源：`logs/{exp_dir}/{exp_name}.csv`*
```

---

## 模板 B：QPS 拐点 / 对比报告

> 适用：`qps-benchmark-sweep` + `qps-sweep-comparison` Skill 执行后生成

```markdown
# {model_name}：{配置描述} QPS 拐点报告

> **测试时间**：{YYYY-MM-DD}  
> **测试配置**：{TP/DP 方案，如 "4TP×1实例 vs 1TP×4DP"}  
> **结论**：{一句话核心结论，含拐点 QPS 和 SLA 基准}

---

## 一、测试背景

### 1.1 测试配置

| 参数 | {配置A} | {配置B，对比时填写} |
|------|---------|-----|
| 部署方式 | {如 TP=4, DP=1} | {如 TP=1, DP=4} |
| 扫描档位数 | {N} 档 | {M} 档 |
| QPS 范围 | {lo} → {hi} req/s | {lo} → {hi} req/s |
| 每档时长 | {T}s（{T/60}min）| 同左 |
| 数据集 | `{dataset_filename}`（{cnt} 条）| 同左 |
| max_completion_tokens | {N} | 同左 |

### 1.2 SLA 基准

| 指标 | 门限 | 说明 |
|------|------|------|
| **{主判断指标，如 E2E P95}** | **{门限值}** | 主判断指标 |
| {辅助指标，如 TTFS P90} | {门限值} | 辅助判断 |
| 请求成功率 | ≥ 99% | 稳定性基准 |

<!-- 有异常档位剔除时填写 -->
<!--
### 1.3 异常档位剔除说明

| 剔除档位 | 原因 |
|---------|------|
| {qps_X} | {原因，如 KV Cache 热身效应导致非稳态} |
-->

---

## 二、SLA 合规结果汇总

<!-- 单组时用简单汇总表，多组对比时用对比表 -->

| 部署配置 | 档位数 | SLA 合规最大 QPS | 拐点类型 | 说明 |
|---------|--------|----------------|---------|------|
| **{配置A}** | {N} 档 | **{qps} req/s（{rpm} RPM）** | {软/硬}拐点 | {触发条件描述} |
| {配置B} | {M} 档 | {qps / None（全档不达标）} | — | {说明} |

---

## 三、逐档 SLA 明细

### 3.1 {配置A}

| QPS (req/s) | {主指标} | {辅指标} | 成功率 | SLA |
|------------|---------|---------|--------|-----|
| {lo} ~ {x} | {range} | {range} | {n}% | ✅ PASS（线性区）|
| **{inflection}** | **{val}** | **{val}** | **{n}%** | **✅ PASS（上限）** |
| {inflection+step} | {val} ⚠️ | {val} | {n}% | ❌ FAIL |
| {hi} | {val} | {val} | {n}% | ❌ FAIL |

<!-- 多组对比时复制上表，修改标题为 ### 3.2 {配置B} -->

---

## 四、拐点分析

### 4.1 拐点结论

| 配置 | SLA 合规最大 QPS | 拐点说明 |
|------|----------------|---------|
| **{配置A}** | **{qps} req/s（{rpm} RPM）** | {触发指标} 在 QPS={x} 时首次超标 |
| {配置B} | {结论} | {原因} |

### 4.2 阶段分布（以 {配置A} 为例）

| 阶段 | QPS 区间 | {主指标} | 描述 |
|------|---------|---------|------|
| 稳定低延迟区 | {lo} ~ {x1} | {range} | 延迟极低，余量充足 |
| 平稳增长区 | {x1} ~ {x2} | {range} | 小幅线性抬升 |
| **拐点** | **{x2} → {x2+step}** | {val} → {val} ⚠️ | **{主指标} 首次突破门限** |
| 过载区 | {x2+step} ~ {hi} | {range} | 持续超标 |

<!-- 多组对比时添加根因分析 -->
<!--
### 4.3 {配置B} 不达标根因

{说明为什么某配置表现差：如 prefill 瓶颈、KV Cache 命中率、网络拓扑等}
-->

---

## 五、部署建议

### 5.1 推荐配置

**推荐**：使用 {配置A}，原因：{一句话}

### 5.2 扩容计算

| 参数 | 值 |
|------|-----|
| 业务峰值 QPS | {biz_peak_qps} req/s（{biz_peak_rpm} RPM）|
| 单实例合规最大 QPS | {inflection_qps} req/s × 0.9（留 10% 余量）|
| 所需实例数 | ceil({biz_peak_qps} / ({inflection_qps} × 0.9)) = **{n} 实例** |
| GPU 总量 | {n} 实例 × {gpus_per_instance} 张 {gpu_type} = **共 {total_gpus} 卡** |

---

## 六、附录

### 6.1 实验数据索引

| 实验目录 | 类型 | 档位数 | 关键结论 |
|---------|------|--------|---------|
| `logs/{exp_dir_A}/` | {配置A} QPS 扫描 | {N} 档 | 拐点 {qps} req/s |
| `logs/{exp_dir_B}/` | {配置B} QPS 扫描 | {M} 档 | {结论} |

### 6.2 可视化文件

| 文件 | 说明 |
|------|------|
| `plot_qps.html` | QPS vs 成功率（N组交互式对比）|
| `plot_throughput.html` | QPS vs 吞吐量 |
| `plot_latency_2d.html` | QPS vs {主延迟指标} P90/P95/P99 |

---

*报告生成时间：{YYYY-MM-DD}*
```

---

## 三种报告的层级关系速查

```
实验级（本文件）
  results/{exp_dir}/REPORT.md
  ├── 模板 A：回放压测报告
  └── 模板 B：QPS 拐点报告
        ↓ 关键数值提取
模型级结构化上下文
  results/models/{model}/model-context.md   ← AI 工作流 YAML
        ↓ 综合汇总
模型级交付报告
  results/models/{model}/EVAL_REPORT.md     ← 面向业务方
```

**每层的角色：**
- `REPORT.md`：单次实验的完整记录，保留过程细节和有效性论证，供技术复查
- `model-context.md`：机器可读的数字提取，驱动 AI 自动生成 EVAL_REPORT
- `EVAL_REPORT.md`：跨实验的结论汇总，面向业务方和资源规划
