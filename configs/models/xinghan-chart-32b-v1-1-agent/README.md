# xinghan-chart-32b-v1-1-agent  特例说明

> 模型汇总：`results/models/xinghan-chart-32b-v1-1-agent/model-context.md`  
> 数据说明：`clingo/docs/ai_data/xinghan-chart-32b-v1-1-agent-data-structure.md`

---

## 特例记录

| 日期 | 参数 | 特殊值 | 原因 |
|------|------|--------|------|
| 2026-03-18 | `DATA_FORMAT` | `indexed` | chart JSONL 是 SpecForge 索引文件，messages 字段是 COS URL，非内联 list |
| 2026-03-18 | `DURATION` | `1500`（非标 `2700`）| 有效数据仅 6,016 条（总 47,338 中的 12.7%），QPS_END×2700=10,800 会超限 |
| 2026-03-18 | 有效数据率 | 12.7% | 41,320 条为 Agent 框架调用（`model=星盘普通`），prompt 动态生成不持久化，无法用于 benchmark |

## 数据处理流程

chart 数据需要两阶段处理，与标准流程（guoxue/ziwei）不同：

```
索引 JSONL (47,338条)
    │
    ▼ download_by_indices.py（SpecForge 工具）
downloaded_raw.jsonl (47,338条，739MB，每行 JSON array)
    │
    ▼ process.py --env 8tp.env（DATA_FORMAT=indexed）
xinghan-chart-32b-v1-1-agent_all.csv (6,016条，有效数据)
```

## 未来 Replay 计划

sweep 完成后（预计 2026-03-19），确认拐点 QPS 后：

1. 将 `REPLAY_RPM` 设为拐点 QPS × 60 的 120%（放大验证）
2. 用 SpecForge 的 poisson 插值脚本生成 `_poisson_<RPM>_stitched.csv`
3. 更新 `REPLAY_DATASET_PATH` 和 `REPLAY_RPM`
4. 运行 `bash scripts/benchmark/run_replay.sh 8tp.env`
