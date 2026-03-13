# scripts/

模型部署迁移评估的工作脚本库，按功能分目录。`tmp/` 保留为临时草稿区。

```
scripts/
├── deploy/         Docker 容器启动脚本（每个模型一个）
├── benchmark/      QPS 扫描 & 压力测试执行脚本
├── probe/          服务探针脚本（探测模型行为 / 测试远端连通性）
├── data/           数据处理脚本（JSONL→CSV，峰值采样，插值，脏数据过滤）
└── analysis/       结果分析脚本（多批次结果合并，统计汇总）
```

## deploy/

| 脚本 | 模型 | 端口 | GPU |
|------|------|------|-----|
| `start_ziwei_32b.sh` | xinghan-ziwei-32b-v1 | 5290 | 1,3,4,5（TP=4）|
| `start_ziwei_8b.sh` | ziwei-intention-8b | 5291 | 单卡 |
| `start_tianji_querysafety_4b.sh` | tianji-querysafety-4b-v2-3 | 8361 | 3,4,5,6（TP=4）|

## benchmark/

| 脚本 | 用途 |
|------|------|
| `run_tianji_querysafety_qps_sweep.sh` | tianji-querysafety-4b QPS 扫描（6.0→4.0，30档，每档45min）|
| `run_ziwei_4tp_qps_benchmark.sh` | ziwei 32B 4TP 基准 QPS 扫描 |
| `run_ziwei_8tp_qps_stress.sh` | ziwei 32B 8TP 高强度压力测试 |
| `run_ziwei_4tp_high_qps_explore.sh` | 4TP 高 QPS 边界探索（QPS 1.0~2.0）|
| `run_ziwei_8tp_high_qps_explore.sh` | 8TP 高 QPS 边界探索（QPS 1.1~2.0）|

## probe/

| 脚本 | 用途 |
|------|------|
| `probe_models.py` | ziwei 本地实例探测（意图分类 + 对话响应）|
| `probe_tianji_querysafety.py` | tianji 安全拦截行为探测 + 准确率统计 |
| `test_remote_services.py` | 远端 k8s 服务连通性验证 |

## data/

执行顺序与数据处理链路对应（详见 Skill：`traffic-dataset-prep`）：

| 脚本 | 步骤 | 用途 |
|------|------|------|
| `process_ziwei_full.py` | 步骤1-3 | JSONL→CSV，峰值采样，泊松插值（一体化）|
| `process_ziwei_all.py` | 步骤1+合并 | 按天 CSV 合并为 `_all.csv`，过滤脏数据 |
| `make_peak100_stitched.py` | 步骤3-4 | 时间戳拼接 + 插值至 100 RPM |
| `fix_all_csv_list_content.py` | 步骤5（独立）| 单独修复 `_all.csv` 中的多模态脏行 |

## analysis/

| 脚本 | 用途 |
|------|------|
| `merge_4tp_qps_20260310.py` | 合并三批 4TP 压测结果到统一目录结构 |
