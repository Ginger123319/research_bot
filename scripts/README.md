# scripts/

模型部署迁移评估的工作脚本库，按功能分目录。

```
scripts/
├── deploy/         Docker 容器启动脚本（每个模型一个）
├── benchmark/      QPS Peak Finder + 回放 + 扫描执行脚本
├── probe/          服务探针脚本（探测模型行为 / 测试远端连通性）
├── data/           数据处理脚本（JSONL→CSV，峰值采样，插值，Agent 数据转换）
├── analysis/       结果分析脚本（峰值分析、离线统计、多批次合并）
└── archived/       已归档的历史迁移脚本（保留参考）
```

## deploy/

| 脚本 | 模型 | 端口 | GPU |
|------|------|------|-----|
| `start_ziwei_32b.sh` | xinghan-ziwei-32b-v1 | 5290 | 1,3,4,5（TP=4）|
| `start_ziwei_8b.sh` | ziwei-intention-8b | 5291 | 单卡 |
| `start_tianji_querysafety_4b.sh` | tianji-querysafety-4b-v2-3 | 8361 | 3,4,5,6（TP=4）|

## benchmark/

### QPS Peak Finder（三阶段自动化）

> 命名规范：`run_phase{1|2|3}_{auto|grid}_<model>_<config>.sh`

| 脚本前缀 | 模型 / 配置 |
|----------|-----------|
| `run_peak_finder_chart_agent.sh` | chart-32b-agent 统一入口（4TP/8TP）|
| `run_phase1_auto_chart_agent_{4tp\|8tp}.sh` | chart-32b-agent Phase 1 饱和探测 |
| `run_phase{1\|2\|3}_*_chart_agent_{4tp\|8tp}.sh` | chart-32b-agent 各阶段 |
| `run_phase{1\|2\|3}_*_guoxue_{eagle3\|eagle3_4h20\|4h20}.sh` | guoxue-72b Eagle3/H20 各阶段 |
| `run_phase{1\|2\|3}_*_guoxue8tp_v2.sh` | guoxue-72b vanilla 8×L20 |
| `run_phase{1\|2\|3}_*_chart_deep_8h20.sh` | chart-deep-v5-2-235B 8×H20 |
| `run_phase{1\|2\|3}_*_chart{4tp\|8tp}.sh` | chart-32b（旧版，非 agent）|
| `run_phase1_auto_{tianji4tp_bakv1\|ziwei8tp}.sh` | tianji / ziwei 补跑 |
| `run_phase1_saturation.sh` | 通用饱和测试（手动参数）|

### 回放与锚点

| 脚本 | 用途 |
|------|------|
| `run_replay.sh` | 通用回放（手动参数）|
| `run_ziwei_peak_replay.sh` | ziwei 生产峰值回放 |
| `run_prod_anchor_guoxue8tp.sh` | guoxue L20 生产锚点单档补测（0.195 req/s）|
| `watch_and_relay_*.sh` | 中继监控脚本（chart-deep / guoxue-eagle3）|

### 旧版 QPS Sweep（已存档，仍可用）

| 脚本 | 用途 |
|------|------|
| `run_chart_{4tp\|8tp}_qps_sweep.sh` | chart-32b 旧版扫描 |
| `run_guoxue_8tp_qps_sweep.sh` | guoxue 旧版扫描 |
| `run_tianji_querysafety_qps_sweep.sh` | tianji 旧版扫描 |
| `run_ziwei_{4tp\|8tp}_*.sh` | ziwei 各档 QPS 探索 |

## probe/

| 脚本 | 用途 |
|------|------|
| `probe_models.py` | ziwei 本地实例探测（意图分类 + 对话响应）|
| `probe_tianji_querysafety.py` | tianji 安全拦截行为探测 + 准确率统计 |
| `test_remote_services.py` | 远端 k8s 服务连通性验证 |

## data/

执行顺序与数据处理链路对应（详见 Skill：`traffic-dataset-prep`）：

| 脚本 | 用途 |
|------|------|
| `process_ziwei_full.py` | ziwei：JSONL→CSV，峰值采样，泊松插值 |
| `process_ziwei_all.py` | ziwei：按天合并为 `_all.csv`，过滤脏数据 |
| `process_chart_full_v3.py` | chart-32b：全量数据处理（V3）|
| `process_guoxue_full.py` | guoxue：全量处理（V1 兜底数据）|
| `process_guoxue_v2.py` | guoxue：V2 真实数据处理 |
| `process_tianji_querysafety_full.py` | tianji：数据处理 |
| `process_henpan_tarot_full.py` | hepan/tarot：数据处理 |
| `make_peak100_stitched.py` | 时间戳拼接 + 插值至目标 RPM |
| `fix_all_csv_list_content.py` | 修复 `_all.csv` 中的多模态脏行 |
| `extract_agent_calls.py` | chart-agent：提取 Agent 框架调用记录（含 prompt2）|
| `convert_chart_agent_prompt2.py` | chart-agent：批量将 prompt2 转换为 messages |
| `prep_chart_agent_dataset.py` | chart-agent：Agent 数据集整备 |

## analysis/

| 脚本 | 用途 |
|------|------|
| `analyze_peak_finder.py` | QPS Peak Finder 三阶段分析（Phase 0 全量 tokenize + Phase 1 checkpoint + Phase 2/3 容量曲线）|
| `offline_analysis.py` | 回放/压测结果离线统计（CDF 图、HTML 报告、7 张 PNG）|
| `compare_analysis.py` | 多配置对比分析（TP4 vs TP8 等）|
| `build_badcase_csv.py` | 构建 bad case 分析 CSV |
| `extract_null_decode.py` | 提取 decode 为空的异常记录 |
| `merge_4tp_qps_20260310.py` | 合并早期 4TP 压测批次结果（历史用）|

## archived/

| 脚本 | 说明 |
|------|------|
| `migrate_chart_outputs.sh` | chart-agent 输出目录迁移至 `used4evaluation/` |
| `migrate_datas_to_used4evaluation.sh` | 数据集批量迁移脚本 |
