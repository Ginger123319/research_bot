# configs/models  共性发现

此文档记录跨模型共性特例，积累到一定数量后会推动通用脚本迭代。

---

## 共性发现

| 发现时间 | 模型 | 现象 | 原因 | 影响参数 |
|---------|------|------|------|---------|
| 2026-03-18 | chart | JSONL 是索引文件，非直接数据 | SpecForge 的 raw_content 存储模式 | `DATA_FORMAT=indexed` |
| 2026-03-18 | chart | 有效数据仅 12.7% | Agent 框架调用不持久化 prompt | `DURATION` 需按实际行数缩短 |

---

## 目录结构

```
configs/models/
├── README.md                              ← 本文件（共性发现）
├── xinghan-chart-32b-v1-1-agent/
│   ├── 8tp.env                            ← 8TP 部署配置
│   ├── 4tp.env                            ← 4TP 部署配置（对照）
│   └── README.md                          ← 模型特例说明
└── <next-model>/
    ├── 8tp.env
    └── README.md
```

---

## 接入新模型步骤

```bash
# 1. 创建目录
mkdir -p configs/models/<model-name>

# 2. 参照已有 .env 创建配置
cp configs/models/xinghan-chart-32b-v1-1-agent/8tp.env \
   configs/models/<model-name>/8tp.env
# 修改：MODEL_NAME / MODEL_PATH / SERVER_URL / GROUP_NAME /
#       DATA_FORMAT / INPUT_JSONL / QPS_* / DURATION 等

# 3. 数据处理
python scripts/data/process.py --env configs/models/<model-name>/8tp.env

# 4. QPS sweep
nohup bash scripts/benchmark/run_qps_sweep.sh \
    configs/models/<model-name>/8tp.env \
    > logs/data-pipeline/<model>_8tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# 5. replay（sweep 完成后）
# 更新 REPLAY_DATASET_PATH 和 REPLAY_RPM 后
nohup bash scripts/benchmark/run_replay.sh \
    configs/models/<model-name>/8tp.env \
    > logs/data-pipeline/<model>_8tp_replay_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```
