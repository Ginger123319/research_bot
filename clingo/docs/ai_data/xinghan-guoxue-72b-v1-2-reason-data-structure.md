# xinghan-guoxue-72b-v1-2-reason 数据结构说明

> 记录该模型从原始 JSONL 到 benchmark 可用 CSV 的完整处理链路，
> 以及 `old_response` 回填问题的根因与修复方案。
>
> **本文档覆盖两个版本的数据集：**
> - **V1（标准格式）**：2026-03-13~14 线上日志，每行是 dict（情况A），已完成处理
> - **V2（AI-data 导出格式）**：2026-01-16~17 线上日志，每行是 list（情况C），发现严重的 `old_response` 构建缺陷

---

## 一、数据来源链路

```
线上原始日志（SpecForge）
      │
      ▼
原始 JSONL 文件
  datas/xinghan-guoxue-72b-v1-2-reason_260313_260314.jsonl
  23,362 条  |  2026-03-13 ~ 2026-03-14  |  八字命理会话
      │
      │  DataConverter（process_guoxue_full.py 步骤1）
      ▼
日期分片 CSV（步骤1产物，含 messages 但 old_response 全空）
  datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_2026-03-13.csv  12,126 条
  datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_2026-03-14.csv  11,231 条
      │
      │  步骤1.5：合并 + JSONL 回填 old_response（line_num 映射）
      ▼
全量合并 CSV
  datas/output_guoxue/xinghan-guoxue-72b-v1-2-reason_all.csv
  23,357 条  |  6 列完整数据  |  old_response 非空率 100%
      │
      │  DataSampler（步骤2）：峰值窗口采样
      ▼
峰值窗口采样 CSV
  datas/output_guoxue/..._selected_combined_2days_peak.csv  989 条
      │
      │  时间戳拼接（步骤3）+ 泊松插值（步骤4）+ 脏数据过滤（步骤5）
      ▼
最终可用 benchmark 数据集
  datas/output_guoxue/..._selected_combined_2days_peak_poisson_220_stitched.csv
  5,726 条  |  峰值 220 RPM  |  replay benchmark 使用此文件
```

---

## 二、JSONL 字段结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `session_time` | int (ms) | 业务请求时间 → 对应 CSV `income_time`（Asia/Shanghai）|
| `messages` | list | 多轮对话，角色见下表 |
| `user_id` | str | 用户 ID |

### messages 角色说明

| `role` | 含义 | CSV 映射 |
|--------|------|---------|
| `"b"` | 用户提问（八字问题正文）| 组装进 `messages` 列 |
| `"ib"` | 用户附加信息（"用户发送了八字"等提示）| 组装进 `messages` 列 |
| `"a"` | **模型回复**（含 `<think>` 推理过程）| → `old_response` 列（见下节）|

---

## 三、old_response 回填问题

### 根因

`DataConverter` 在转换 JSONL → CSV 时，**只组装用户侧 messages，不提取 `role='a'` 的模型回复**。
日期分片 CSV 的 `old_response` 列从 DataConverter 输出起就全为 `NaN`，
步骤 1.5 的 `fillna("")` 只是将 NaN 改成空串，并未真正填充内容。

### 映射关系

```
CSV  line_num  =  JSONL 行索引（0-indexed）+ 1
                  即 line_num=1 对应 JSONL 第 0 行
```

验证依据：CSV `income_time` 与 JSONL `session_time`（ms → Asia/Shanghai）完全一一对应。

### 修复方案（已在 process_guoxue_full.py 步骤1.5 实现）

```python
# 构建 line_num → role='a' 内容的映射
line_num_to_resp = {}
with open(JSONL_FILE, encoding='utf-8') as jf:
    for idx, raw in enumerate(jf):
        line_num = idx + 1   # 1-indexed
        record = json.loads(raw)
        resp = next(
            (m.get('content', '') for m in record.get('messages', [])
             if m.get('role') == 'a'),
            ''
        )
        if resp:
            line_num_to_resp[line_num] = resp

# 回填 CSV
df["old_response"] = df["line_num"].map(line_num_to_resp).fillna("")
```

修复后验证结果：
- `_2026-03-13.csv`：回填 12,126 / 12,126 行（**100%**）
- `_2026-03-14.csv`：回填 11,231 / 11,231 行（**100%**）
- `_all.csv`：23,357 / 23,357 行（**100%**）

---

## 四、输出长度分布（Phase 0 预分析）

基于 JSONL 全量 `role='a'` 内容，tokenizer `/mnt/ai-llm/l83v2-G1-400`，采样 500 条：

| 统计 | 字符数 | Token 数 |
|------|--------|---------|
| **Avg** | 2,927 | **2,046** ← 用于换算 max_rps_estimate |
| P50 | 2,912 | 2,021 |
| P90 | 3,436 | 2,421 |
| P99 | 4,043 | 3,123 |

> 注：模型输出包含 `<think>` 推理块（国学长推理模型），实际 token 数显著高于普通对话模型。
> 对应历史压测分析值（单档有效样本）：avg ≈ 1,933 tokens，与全量均值 2,046 接近，数据可信。

---

## 五、benchmark 使用说明

| 场景 | 推荐数据集 | 说明 |
|------|-----------|------|
| QPS 拐点扫描（新方法 qps-peak-finder Phase 1/2）| `_2026-03-13.csv`（12,126 条）| 覆盖足够多档位 |
| 全量 QPS sweep | `_all.csv`（23,357 条）| 最大并发/时长场景 |
| 回放测试（peak traffic replay）| `_poisson_220_stitched.csv`（5,726 条）| 真实流量形态，220 RPM 峰值 |
| 快速单次验证 | `_selected_combined_2days_peak.csv`（989 条）| 峰值窗口原始数据 |

**固定参数**：
```bash
TOKENIZER=/mnt/ai-llm/l83v2-G1-400
MAX_COMPLETION_TOKENS=4096      # 长推理模型，推理+回答总长
SERVER_URL=https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions
```

---

## 六、处理脚本

| 脚本 | 说明 |
|------|------|
| `scripts/data/process_guoxue_full.py` | 完整 6 步数据处理管道（含步骤1.5 old_response 回填）|

---

## 七、V2 数据集（AI-data downloaded 格式）

### 7.1 数据来源

```
AI-data 平台导出（downloaded 格式）
  /mnt/ai-infra/users/wnd/workspace/repo/SpecForge/wnd_dev/data/downloaded/
    guoxue-v1-2-online-2026-01-1631-downloaded-s50k.jsonl
  50,000 条  |  2026-01-16~17  |  采集时段为国学模型上线初期

      │  情况C 自定义解析（跳过 DataConverter / DataSampler）
      ▼
全量合并 CSV（datas/output_guoxue_v2/）
  xinghan-guoxue-72b-v1-2-reason_all.csv
      │
      │  峰值窗口采样 + 时间戳拼接 + 泊松插值（TARGET_RPM=256）
      ▼
最终压测数据集（V2）
  xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv
  508,014 条  |  峰值 256 RPM  |  用于 EAGLE3 4xH20 Phase1/2/3 压测
```

### 7.2 JSONL 行格式（每行是 list，情况C）

每行是一个 list，含若干 role 对象：

```json
[
  {"role": "b",  "content": "用户问题正文", "time": 1768545951000, "_id": "..."},
  {"role": "ib", "content": "用户附加信息（八字数据）", ...},
  {"role": "a",
   "content":        "模型完整回复（含 <con> 结构，见 §7.3）",
   "ai_deep_content": "模型推理过程原文（无 <think> 标签，见 §7.4）",
   "prompt":          "[{\"role\":\"system\",...}]",
   "extra_data":      {"ai_info": {"model": "八字深度", "suffix": "八字深度"}},
   "time": ...}
]
```

| 字段 | CSV 列 | 说明 |
|------|--------|------|
| `role='b'.time`（ms）| `income_time` | 请求时间戳，转 Asia/Shanghai |
| `role='a'.prompt` | `messages` | 完整 system+user messages JSON |
| `role='a'.content` | `old_response`（**含缺陷，见 §7.5**）| 模型历史回复 |
| `role='a'.ai_deep_content` | 未提取（**漏点，见 §7.4**）| 推理过程原文 |
| `role='b'._id` | `user_id` | 用户 ID |
| `extra_data.ai_info.model` | — | 模型别名过滤字段 |

---

## 八、`<con>` 标签的来源与含义

### 8.1 发现

对 V2 原始 JSONL 中 `role='a'.content` 的分析结果：

| 指标 | 数值 |
|------|------|
| 含 `<con></con>` 的行占比 | **61.7%**（30,854 / 50,000 条）|
| 含 `<think></think>` 的行占比 | **0%** |
| `ai_deep_content` 非空率 | **82.0%** |

### 8.2 `<con>` 的真实来源

`<con>` **不是** DataConverter 或 data_processor 加入的，而是 **AI-data 数据存储管道的后处理转换**。

模型原始输出 → AI-data 存储时转换 → 存入 `content` 字段：

```
模型原始输出:
  ## 结论
  {conclusion_text}

  ---

  ## 一、详细分析...

AI-data 存储后（content 字段）:
  <con>## 请输入替换内容 {conclusion_text}</con>

  ---

  ## 一、详细分析...
```

验证依据：50,000 条样本中，含 `<con>` 的行，其 `</con>` 之后正文**100% 不含 `## 结论`**，
即 `<con>` 就是 `## 结论` 段的替换包装，两者语义完全一致。

### 8.3 `<con>` 数据的背景（模型版本差异）

| 时期 | 模型行为 | 数据特征 |
|------|----------|----------|
| 2026-01 数据采集时 | 非推理模型（vanilla fine-tuned）| `content` 有 `<con>`；无 `<think>`；`ai_deep_content` 是推理过程 |
| 2026-03 benchmark 时 | 已升级为推理模型 | 同一端点输出 `<think>` 推理链；不再输出 `<con>` |

**结论**：V2 数据的 `content` 结构与当前模型输出格式**已不一致**，直接使用会严重低估 `avg_output_len`。

---

## 九、`ai_deep_content` 字段说明

### 9.1 字段含义

| 字段 | 含义 |
|------|------|
| `ai_deep_content` | 模型生成结论前的推理过程（对应现在的 `<think>` 块内容），无标签 |
| `content` | 模型最终输出（AI-data 后处理后），不含推理过程 |

二者加在一起，才完整对应当前推理模型的实际输出：
```
<think>{ai_deep_content}</think>
## 结论
{conclusion_text}

---
## 一、详细分析...
```

### 9.2 字段覆盖情况（50K 样本）

| 场景 | 行数 | 占比 |
|------|------|------|
| `ai_deep_content` 非空 | 41,000 | 82% |
| `ai_deep_content` 为空 | 9,000 | 18% |
| `content` 含 `<con>` | 30,854 | 61.7% |
| `content` 不含 `<con>` | 19,146 | 38.3% |

---

## 十、V2 `old_response` 构建缺陷与修复方案

### 10.1 缺陷描述

V2 压测数据集构建时，`old_response` 直接取 `role='a'.content`，存在两个缺陷：

| 缺陷 | 影响 |
|------|------|
| **缺陷1**：未将 `ai_deep_content` 以 `<think>` 包裹并前置 | 漏掉约 700~800 token 的推理链 |
| **缺陷2**：未将 `<con>` 结构转换为 `## 结论` 格式 | `old_response` 格式与当前模型输出不一致 |

### 10.2 量化影响

| 数据来源 | avg token 数 | 说明 |
|----------|-------------|------|
| V2 CSV `old_response`（有缺陷）| **~1,417 tokens** | 仅 content，无推理链 |
| Phase 1 实测 avg_output_len（EAGLE3 4xH20）| **2,204 tokens** | 含 `<think>` 推理块的真实输出 |
| 差值 | **~787 tokens（+55%）** | Phase 0 系统性低估 |

这导致 Phase 1 `max_rps_estimate` 用 1,386 token（Phase 0 AVG）计算，
实际模型输出 2,204 token，**max_rps 被高估约 59%**，Phase 2 启动 RPS 接近真实容量的 2 倍，
造成灾难性过载（success rate 仅 11%，`asyncio.TimeoutError` 占 80%）。

### 10.3 正确的 `old_response` 构建逻辑

处理顺序（两步，顺序不可颠倒）：

**Step 1：`<con>` → `## 结论` 转换（有则转，无则保留）**

```python
import re

def convert_con_to_jielun(content: str) -> str:
    m = re.search(r'<con>(.*?)</con>', content, re.DOTALL)
    if not m:
        return content
    inner = m.group(1).strip()
    inner = inner.replace('## 请输入替换内容', '').strip()
    # </con> 之后原文已含 \n\n---，保留即可
    return content[:m.start()] + f'## 结论\n{inner}' + content[m.end():]
```

**Step 2：`ai_deep_content` → `<think>` 前置（非空时才加）**

```python
def build_old_response(content: str, ai_deep_content: str) -> str:
    result = convert_con_to_jielun(content)
    if ai_deep_content and ai_deep_content.strip():
        result = f'<think>{ai_deep_content.strip()}</think>\n\n' + result
    return result
```

修复后 `old_response` 结构：
```
<think>{ai_deep_content}</think>

## 结论
{conclusion_text}

---

## 一、详细分析...
```

与当前推理模型实际输出**完全一致**。

### 10.4 修复后验证 Checklist

| 检查项 | 期望 |
|--------|------|
| `old_response` 含 `<think>` 的比例 | ≈ 82%（与 `ai_deep_content` 非空率一致）|
| `old_response` 含 `## 结论` 的比例 | ≈ 61.7%（原 `<con>` 占比，转换后应消失）|
| `old_response` 不含 `<con>` | 100%（转换后应清零）|
| 抽样 500 条 avg token 数 | 应接近 Phase 1 实测 avg_output_len（误差 < 20%）|

---

## 十一、Phase 0 avg_output_len 修正建议

| 版本 | avg_output_len | 来源 | 是否可信 |
|------|---------------|------|----------|
| V2 CSV（有缺陷）| **1,386 tokens** | 直接对有缺陷的 `old_response` tokenize | ❌ 低估 55% |
| Phase 1 实测（EAGLE3 4xH20）| **2,204 tokens** | con=260 压测实测 avg | ✅ 最可信 |
| V2 CSV 修复后估算 | **~1,838 tokens** | 模拟加入 `ai_deep_content` 后 tokenize | ✅ 合理参考 |

> **结论**：Phase 1 实测 `avg_output_len` 永远优先于 Phase 0 估算值。
> 若 Phase 1 实测与 Phase 0 估算偏差 > 20%，Phase 2 `START_RPS` 必须基于 Phase 1 实测值重算。
>
> EAGLE3 4xH20 正确 Phase 2 `START_RPS` 应为：
> `0.7925 × (1386 / 2204) ≈ 0.498 req/s`（而非错误使用的 0.951 req/s）
