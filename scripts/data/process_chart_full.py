#!/usr/bin/env python3
"""
xinghan-chart-32b-v1-1-agent 完整数据处理脚本
遵循 traffic-dataset-prep SKILL 6步管道
"""

import sys, os, json, ast
sys.path.insert(0, "/mnt/ai-infra/users/wnd/workspace/execute/guofan/third_party/data_analysis/scripts")

from pathlib import Path
from datetime import datetime
import pandas as pd

# 配置
JSONL_FILE = '/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/xinghan-chart-32b-v1-1-agent_260312_260316.jsonl'
OUTPUT_DIR = '/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_chart'
MODEL_NAME = 'xinghan-chart-32b-v1-1-agent'
MODEL_LIST = ('xinghan-chart-32b-v1-1-agent',)
TARGET_PEAK = 120

# 峰值窗口（3天，凌晨 00:00 附近，各 ±15min）
PEAK_WINDOWS = [
    ('2026-03-13 23:45:00', '2026-03-14 00:15:00', '03-14 峰值00:02 ±15min'),
    ('2026-03-11 23:45:00', '2026-03-12 00:15:00', '03-12 峰值00:02 ±15min'),
    ('2026-03-12 23:45:00', '2026-03-13 00:15:00', '03-13 峰值00:03 ±15min'),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

print('=' * 60)
print('chart-32b 数据处理流程')
print('=' * 60)
print(f'  模型:     {MODEL_NAME}')
print(f'  输出目录: {OUTPUT_DIR}')
print(f'  目标峰值: {TARGET_PEAK} RPM')
print()

# 步骤 1: DataConverter
print('[步骤1] DataConverter 转换 JSONL → CSV')
from scripts.data_processor.modules.converter import DataConverter
converter = DataConverter(
    input_file=JSONL_FILE,
    output_dir=OUTPUT_DIR,
    model_list=MODEL_LIST,
    fetch_prompt=True,
    fetch_response=False,
)
converter.run()
print('  ✅ 日期分片 CSV 生成完成')
print()

# 步骤 1.5: 合并日期分片
print('[步骤1.5] 合并日期分片 → _all.csv')
date_csvs = sorted(Path(OUTPUT_DIR).glob(f'{MODEL_NAME}_*.csv'))
date_csvs = [f for f in date_csvs if '_all.csv' not in f.name]

if not date_csvs:
    print('  ❌ 未找到日期分片 CSV')
    sys.exit(1)

df_list = []
for csv_path in date_csvs:
    df = pd.read_csv(csv_path)
    df_list.append(df)
    print(f'    读取 {csv_path.name}: {len(df)} 行')

df_merged = pd.concat(df_list, ignore_index=True)
df_merged['old_response'] = df_merged['old_response'].fillna('')

all_csv_path = Path(OUTPUT_DIR) / f'{MODEL_NAME}_all.csv'
df_merged.to_csv(all_csv_path, index=False)
print(f'  ✅ 覆盖写回 {all_csv_path.name}: {len(df_merged)} 行')
print()

# 步骤 2: DataSampler
print('[步骤2] DataSampler 峰值窗口采样')
from scripts.data_processor.modules.sampler import DataSampler
sampler = DataSampler(
    input_file=str(all_csv_path),
    output_dir=OUTPUT_DIR,
    model_name=MODEL_NAME,
    peak_windows=PEAK_WINDOWS,
)
sampler.run()
print('  ✅ 峰值窗口采样完成')
print()

# 步骤 3: 时间戳拼接
print('[步骤3] 时间戳拼接')
peak_csv = Path(OUTPUT_DIR) / f'{MODEL_NAME}_peak90min.csv'
if not peak_csv.exists():
    print(f'  ❌ {peak_csv.name} 不存在')
    sys.exit(1)

df_peak = pd.read_csv(peak_csv)
df_peak = df_peak.sort_values('income_time').reset_index(drop=True)

segments = []
current_segment = []
last_time = None

for _, row in df_peak.iterrows():
    if last_time is None:
        current_segment.append(row)
    elif row['income_time'] - last_time > 3600:
        segments.append(current_segment)
        current_segment = [row]
    else:
        current_segment.append(row)
    last_time = row['income_time']

if current_segment:
    segments.append(current_segment)

print(f'    检测到 {len(segments)} 个时间段')

stitched_rows = []
cumulative_offset = 0

for i, seg in enumerate(segments):
    seg_df = pd.DataFrame(seg)
    if i == 0:
        stitched_rows.append(seg_df)
    else:
        prev_last = stitched_rows[-1]['income_time'].iloc[-1]
        seg_first = seg_df['income_time'].iloc[0]
        gap = seg_first - cumulative_offset - prev_last
        cumulative_offset += gap - 1
        seg_df['income_time'] = seg_df['income_time'] - cumulative_offset
        stitched_rows.append(seg_df)

df_stitched = pd.concat(stitched_rows, ignore_index=True)
stitched_csv = Path(OUTPUT_DIR) / f'{MODEL_NAME}_peak90min_stitched.csv'
df_stitched.to_csv(stitched_csv, index=False)
print(f'  ✅ 拼接完成: {stitched_csv.name}, {len(df_stitched)} 行')
print()

# 步骤 4: DataInterpolator
print(f'[步骤4] DataInterpolator 泊松插值 → {TARGET_PEAK} RPM')
from scripts.data_processor.modules.interpolator import DataInterpolator
interpolator = DataInterpolator(
    input_file=str(stitched_csv),
    output_dir=OUTPUT_DIR,
    model_name=MODEL_NAME,
    target_rpm=TARGET_PEAK,
)
interpolator.run()

poisson_csv = Path(OUTPUT_DIR) / f'{MODEL_NAME}_poisson_{TARGET_PEAK}_stitched.csv'
if not poisson_csv.exists():
    print(f'  ❌ {poisson_csv.name} 不存在')
    sys.exit(1)
print(f'  ✅ 泊松插值完成: {poisson_csv.name}')
print()

# 步骤 5: 脏数据过滤
print('[步骤5] 脏数据过滤')
df_final = pd.read_csv(poisson_csv)
print(f'    过滤前: {len(df_final)} 行')

def is_list_content(x):
    if pd.isna(x):
        return False
    try:
        parsed = ast.literal_eval(str(x))
        return isinstance(parsed, list)
    except:
        return False

df_final = df_final[~df_final['messages'].apply(is_list_content)]
df_final.to_csv(poisson_csv, index=False)
print(f'    过滤后: {len(df_final)} 行')
print(f'  ✅ 覆盖写回 {poisson_csv.name}')
print()

# 步骤 6: README
print('[步骤6] 生成 README.md')
readme_path = Path(OUTPUT_DIR) / 'README.md'
with open(readme_path, 'w', encoding='utf-8') as f:
    f.write(f'''# {MODEL_NAME} 数据处理结果

## 处理时间
{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## 输入
- 原始 JSONL: {JSONL_FILE}
- 总条数: {len(df_merged)} 条

## 峰值窗口
{chr(10).join([f'- {desc}: {start} ~ {end}' for start, end, desc in PEAK_WINDOWS])}

## 输出文件
- `{MODEL_NAME}_all.csv`: 完整数据（6 列）
- `{MODEL_NAME}_peak90min.csv`: 峰值窗口采样（3 × 30min）
- `{MODEL_NAME}_peak90min_stitched.csv`: 时间戳拼接
- `{MODEL_NAME}_poisson_{TARGET_PEAK}_stitched.csv`: 泊松插值至 {TARGET_PEAK} RPM（**benchmark 使用**）

## 最终数据集
- 文件: `{poisson_csv.name}`
- 行数: {len(df_final)}
- 目标 RPM: {TARGET_PEAK}
- SLA 标准: TTFS P90 < 1.8s, E2E P90 < 180s

## 使用方式
```bash
DATASET_PATH='{poisson_csv}'
NUM_PROMPTS=$(echo 'qps * 2700' | bc)  # 45min/档
```
''')

print(f'  ✅ README.md 已生成: {readme_path}')
print()

print('=' * 60)
print('✅ 数据处理完成！')
print('=' * 60)
print(f'benchmark 数据集: {poisson_csv}')
print(f'总行数: {len(df_final)}')
print()
