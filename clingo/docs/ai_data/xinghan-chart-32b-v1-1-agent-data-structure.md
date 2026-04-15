# xinghan-chart-32b-v1-1-agent 数据结构说明

> 说明为什么从 47,338 条索引记录中，只有 **6,016 条（12.7%）** 可用于 QPS benchmark 评估。

---

## 一、数据来源链路

```
线上原始日志（SpecForge）
      │
      ▼
索引文件（index JSONL）
  datas/xinghan-chart-32b-v1-1-agent_260312_260316.jsonl
  47,338 条，每条仅含 raw_content URL
      │
      │  download_by_indices.py（多线程下载）
      ▼
下载文件（downloaded_raw JSONL）
  datas/output_chart/xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl
  47,338 条，每条为 JSON Array，含完整会话
      │
      │  process_chart_full_v3.py（过滤 + 转换）
      ▼
benchmark 数据集
  datas/output_chart/xinghan-chart-32b-v1-1-agent_all.csv
  6,016 条，QPS sweep 直接使用
```

---

## 二、索引文件格式

`xinghan-chart-32b-v1-1-agent_260312_260316.jsonl` 中每条记录是一个 **索引**，
`messages` 和 `raw_content` 字段均为 COS URL，指向存储在对象存储中的实际对话内容：

```json
{
  "id": "xxxx",
  "messages": "https://cos.ap-guangzhou.myqcloud.com/...url...",
  "raw_content": "https://cos.ap-guangzhou.myqcloud.com/...url..."
}
```

> 与 guoxue/ziwei 数据格式的区别：guoxue/ziwei 的 `messages` 字段是**内联 list**，可直接用
> `DataConverter` 处理；chart 是 URL，DataConverter 内部 `isinstance(msgs, list)` 判断失败，
> 输出 0 条。必须先用 `download_by_indices.py` 下载 `raw_content` 获取实际内容。

---

## 三、下载后的数据结构

每条下载后的记录是一个 **JSON Array**，固定包含 3 个 role：

```
[
  { role: "b",  ...},   # 用户消息（b = browser/用户侧）
  { role: "ib", ...},   # 中间层消息（ib = inner bridge，对话摘要）
  { role: "a",  ...}    # AI 回复（a = assistant）
]
```

**关键字段全在 `role=a` 的记录中**：

| 字段 | 含义 |
|------|------|
| `extra_data.ai_info.model` | 实际调用的模型名称 |
| `extra_data.ai_info.bot_id` | 调用方 bot 的 ID（区分直接调用 vs Agent） |
| `prompt` | 发给模型的完整消息列表（list or 空 list） |
| `prompt2` | 结构化输入参数（仅 Agent 框架记录有效） |
| `content` | 模型的回复内容 |
| `time` | AI 回复时间戳（ms） |

---

## 四、数据分类：两种调用模式

下载后的 47,338 条记录按 `role=a.extra_data.ai_info.model` 分为**两类**：

| 类型 | model 字段 | bot_id | 条数 | 占比 |
|------|-----------|--------|------|------|
| 直接调用 | `xinghan-chart-32b-v1-1-agent` | `aiChatGeniu` | **6,016** | **12.7%** |
| Agent 框架调用 | `星盘普通` | `agen1754fc4ce3864211b572f4dc54d3` | 41,320 | 87.3% |
| 其他/异常 | — | — | 2 | <0.1% |

---

## 五、有效数据：直接调用（6,016 条）

**调用链**：用户 → 前端 → **直接调用 `xinghan-chart-32b-v1-1-agent` 模型**

`role=a.prompt` 字段为**内联 list**，包含完整的 `system` + `user` 消息：

```json
{
  "role": "a",
  "extra_data": {
    "ai_info": {
      "bot_id": "aiChatGeniu",
      "model": "xinghan-chart-32b-v1-1-agent"
    }
  },
  "prompt": [
    {
      "role": "system",
      "content": "#UserInfo:\n{\"ST\":0,\"year\":2003,\"timezone\":-8,\"sex\":\"f\",\"model_type\":\"xinghan-chart-...\"}"
    },
    {
      "role": "user",
      "content": "我什么时候可以有甜甜的恋爱"
    }
  ],
  "content": "\n**你将在2028年有甜甜的恋爱机会**，那时你25岁左右..."
}
```

- `prompt[0]`（system）：约 360 字符，包含用户出生信息 JSON
- `prompt[1]`（user）：用户提问，通常 9–22 字符
- **可直接用于 benchmark 请求重放**

**时间范围**：2026-03-11 00:00 ~ 2026-03-15 23:58（5天）

---

## 六、无效数据：Agent 框架调用（41,320 条）

**调用链**：用户 → 前端 → **Agent（`agen1754fc4ce3864211b572f4dc54d3`）** → 调用 `星盘普通` → 模型

在 Agent 框架下，系统提示由 Agent 在运行时**动态构建**（包含实时占星计算：行星位置、宫位相位等），
**不写入 `raw_content`**。因此 `role=a.prompt` 字段为空 list：

```json
{
  "role": "a",
  "extra_data": {
    "ai_info": {
      "bot_id": "agen1754fc4ce3864211b572f4dc54d3",
      "model": "星盘普通"
    }
  },
  "prompt": [],          ← 空！Agent 动态生成，不持久化
  "prompt2": "{\"client_time_str\":\"2026-03-11 23:17:39\",\"profile_info_list\":{\"year\":2007,\"timezone\":-8,\"sex\":\"f\",...},\"chart_ext_param\":[...],\"inference_parameters\":{...},\"query\":\"...\"}",
  "content": "<con>\n\n## 是的，你拒绝转专业的机会是对的。..."
}
```

`prompt2` 字段只有结构化**输入参数**（出生信息 + 占星配置），不含最终发给模型的 prompt 文本：

```json
{
  "client_time_str": "2026-03-11 23:17:39",
  "profile_info_list": {
    "year": 2007, "month": 8, "day": 8,
    "hour": 9, "minute": 2,
    "timezone": -8, "sex": "f",
    "cx": "126:33E", "cy": "43:53N"
  },
  "model_name": "chart_agentv1_32B",
  "chart_ext_param": [
    {
      "chart_type": "0",
      "data": { "sunTh": 15, "moonTh": 12, ... }   ← 占星相位计算配置
    }
  ],
  "query": "我拒绝转专业的机会是对的吗"
}
```

**为什么无法还原 prompt？**

Agent 拿到 `prompt2` 后，会调用占星计算引擎（非 LLM），根据出生信息实时生成完整星盘数据
（行星坐标、宫位角度、相位表等），再将这些计算结果填入 system prompt 模板，最终得到一个
几千字的动态 system prompt。**这个计算过程在 Agent 服务内部完成，结果不存储**，
`raw_content` 中没有任何中间产物。

如果要重建，需要复现整套占星计算逻辑（Placidus house system、行星精历表等），
即使重建成功，结果也会因计算时间不同产生微小差异，无法还原历史现场请求。

---

## 七、数据过滤汇总

```
原始索引:          47,338 条
  ↓ download_by_indices.py 全量下载（成功率 100%）
downloaded_raw:    47,338 条
  ↓ 过滤 model ≠ {xinghan-chart-32b-v1-1-agent, 星盘普通}
  → 丢弃 2 条（其他/异常）
  ↓ 过滤 prompt = []（Agent 框架调用）
  → 丢弃 41,320 条（星盘普通 Agent 记录）
  ↓ 脏数据过滤（content 为 list 等格式异常）
  → 丢弃 0 条
最终有效:          6,016 条  ✅
```

---

## 八、对 QPS Benchmark 的影响

| 参数 | 原计划 | 实际调整 | 原因 |
|------|--------|---------|------|
| 每档时长 | 2700s（45min） | **1500s（25min）** | QPS=4.0×2700=10,800 > 6,016 条，会触发数据复用 |
| 数据集 | `_poisson_120_stitched.csv` | **`_all.csv`**（6,016 行） | QPS sweep 无需峰值采样，全量直接使用 |
| 预计总时长 | ~16h | **~8.8h** | 20档 × (1500+90)s |

> **数据充足性验证**：最高档 QPS=4.0 × 1500s = 6,000 < 6,016 条，不会触发数据循环复用。✅

---

## 九、相关文件

| 文件 | 说明 |
|------|------|
| `datas/xinghan-chart-32b-v1-1-agent_260312_260316.jsonl` | 原始索引（47,338 条 URL 引用） |
| `datas/output_chart/xinghan-chart-32b-v1-1-agent_downloaded_raw.jsonl` | 下载后原始数据（739MB） |
| `datas/output_chart/xinghan-chart-32b-v1-1-agent_all.csv` | benchmark 数据集（6,016 行，~16MB） |
| `scripts/data/process_chart_full_v3.py` | 转换脚本（过滤 + 生成 _all.csv） |
| `scripts/benchmark/run_chart_8tp_qps_sweep.sh` | 8TP QPS sweep 脚本 |
| `scripts/benchmark/run_chart_4tp_qps_sweep.sh` | 4TP QPS sweep 脚本 |
