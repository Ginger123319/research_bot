# xinghan-guoxue-72b-v1-2-reason 数据结构说明

> 记录该模型从原始 JSONL 到 benchmark 可用 CSV 的完整处理链路，
> 以及 `old_response` 回填问题的根因与修复方案。

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
