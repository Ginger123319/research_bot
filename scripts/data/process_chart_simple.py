#!/usr/bin/env python3
"""
chart-32b 简化数据处理脚本
直接用 pandas 处理，不依赖 DataConverter
"""

import json
import pandas as pd
from pathlib import Path
from datetime import datetime

# 配置
JSONL_FILE = '/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/xinghan-chart-32b-v1-1-agent_260312_260316.jsonl'
OUTPUT_DIR = '/mnt/ai-infra/users/wnd/workspace/execute/guofan/datas/output_chart'
MODEL_NAME = 'xinghan-chart-32b-v1-1-agent'

Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

print('=' * 60)
print('chart-32b 简化数据处理')
print('=' * 60)

# 步骤 1: 读取 JSONL，提取时间戳和 messages URL
print('[1/3] 读取 JSONL...')
rows = []
with open(JSONL_FILE, 'r') as f:
    for line in f:
        d = json.loads(line)
        rows.append({
            'income_time': d['session_time'] / 1000,  # 毫秒 → 秒
            'messages': d['messages'],
            'prompt': '',  # benchmark 需要这个列
            'old_response': ''  # benchmark 需要这个列
        })

df = pd.DataFrame(rows)
print(f'  总行数: {len(df)}')

# 步骤 2: 峰值窗口采样（3 × 30min）
print('[2/3] 峰值窗口采样...')
df['dt'] = pd.to_datetime(df['income_time'], unit='s')

windows = [
    ('2026-03-13 23:45:00', '2026-03-14 00:15:00'),
    ('2026-03-11 23:45:00', '2026-03-12 00:15:00'),
    ('2026-03-12 23:45:00', '2026-03-13 00:15:00'),
]

dfs = []
for start, end in windows:
    mask = (df['dt'] >= start) & (df['dt'] < end)
    dfs.append(df[mask])
    print(f'    {start} ~ {end}: {mask.sum()} 行')

df_peak = pd.concat(dfs, ignore_index=True)
df_peak = df_peak.sort_values('income_time').reset_index(drop=True)
print(f'  合计: {len(df_peak)} 行')

# 步骤 3: 泊松插值（简化版：直接复制数据达到 120 RPM）
print('[3/3] 泊松插值至 120 RPM...')

# 当前 RPM
duration_min = (df_peak['income_time'].max() - df_peak['income_time'].min()) / 60
current_rpm = len(df_peak) / duration_min
target_rpm = 120
scale_factor = target_rpm / current_rpm

print(f'    当前 RPM: {current_rpm:.1f}')
print(f'    目标 RPM: {target_rpm}')
print(f'    放大倍数: {scale_factor:.2f}x')

# 简化插值：重复数据
n_copies = int(scale_factor)
df_final = pd.concat([df_peak] * n_copies, ignore_index=True)

# 重新分配时间戳（均匀分布）
df_final = df_final.sort_values('income_time').reset_index(drop=True)
t_start = df_final['income_time'].iloc[0]
t_end = df_final['income_time'].iloc[-1]
df_final['income_time'] = pd.Series(range(len(df_final))) * (t_end - t_start) / len(df_final) + t_start

print(f'    最终行数: {len(df_final)}')

# 保存
output_csv = Path(OUTPUT_DIR) / f'{MODEL_NAME}_poisson_120_stitched.csv'
df_final[['income_time', 'messages', 'prompt', 'old_response']].to_csv(output_csv, index=False)

print()
print('=' * 60)
print('✅ 数据处理完成！')
print('=' * 60)
print(f'输出文件: {output_csv}')
print(f'总行数: {len(df_final)}')
print(f'预估 RPM: {len(df_final) / duration_min / n_copies:.1f}')
print()
