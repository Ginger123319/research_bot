#!/usr/bin/env python3
"""
对比分析两次回放测试结果：
- 旧回放：2026-03-28（--context-length 8192 限制）
- 新回放：2026-03-29（取消上下文限制）
"""
import sys, os, json, re
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark/src'))
from llm_benchmark.analysis.analysis.single_exp import load_exp_csv, analysis_row
import pandas as pd

def analyze_csv(csv_path, label):
    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"  CSV: {csv_path}")
    print(f"{'='*60}")

    df, err = load_exp_csv(csv_path)
    print(f"总行数: {len(df)}")
    print(f"status 分布: {df['status'].value_counts().to_dict()}")

    ok_idxs, err_idxs = [], []
    for i, row in df.iterrows():
        try:
            info = analysis_row(row)
            (ok_idxs if info['analysis_status'] == 'data_ok' else err_idxs).append(i)
        except Exception as e:
            err_idxs.append(i)

    print(f"data_ok:    {len(ok_idxs)}")
    print(f"data_error: {len(err_idxs)}")
    print(f"成功率:     {len(ok_idxs)/len(df)*100:.2f}%")

    if err_idxs:
        df_err = df.iloc[err_idxs]
        tl_lens = df_err['token_list'].apply(lambda x: len(x) if isinstance(x, list) else 0)
        print(f"data_error token_list_len分布: {tl_lens.value_counts().to_dict()}")
        # 检查错误类型
        ctx_overflow_cnt = 0
        other_err_cnt = 0
        for idx in err_idxs:
            row = df.iloc[idx]
            rr = row['raw_response']
            found_overflow = False
            for item in rr:
                d = item.get('data', '')
                msg = ''
                if isinstance(d, dict) and 'error' in d:
                    msg = d['error'].get('message', '')
                elif isinstance(d, str) and '{' in d:
                    try:
                        obj = json.loads(d)
                        msg = obj.get('error', {}).get('message', '')
                    except:
                        pass
                if 'token count exceeds' in msg or 'context length' in msg:
                    found_overflow = True
                    break
            if found_overflow:
                ctx_overflow_cnt += 1
            else:
                other_err_cnt += 1
        print(f"  ├─ 上下文超长拒绝: {ctx_overflow_cnt} 条")
        print(f"  └─ 其他错误:      {other_err_cnt} 条")
    else:
        print("✅ 无 data_error！")

    # 延迟指标
    metrics = []
    for i in ok_idxs:
        row = df.iloc[i]
        info = analysis_row(row)
        metrics.append({'ttfs': info['ttfs'], 'e2e': info['e2e'], 'ttft': info['ttft']})
    df_m = pd.DataFrame(metrics)
    print(f"\n延迟指标 (基于 {len(df_m)} 条成功请求):")
    for col in ['ttft', 'ttfs', 'e2e']:
        print(f"  {col}: mean={df_m[col].mean():.3f}s  p50={df_m[col].quantile(0.5):.3f}s  p90={df_m[col].quantile(0.9):.3f}s  p99={df_m[col].quantile(0.99):.3f}s")

    return {
        'total': len(df),
        'ok': len(ok_idxs),
        'err': len(err_idxs),
        'rate': len(ok_idxs)/len(df)*100,
        'ttft_p90': df_m['ttft'].quantile(0.9),
        'ttfs_p90': df_m['ttfs'].quantile(0.9),
        'e2e_p90': df_m['e2e'].quantile(0.9),
        'e2e_mean': df_m['e2e'].mean(),
    }


def main():
    BASE = '/mnt/ai-infra/users/wnd/workspace/execute/guofan'
    old_csv = f'{BASE}/logs/chart-deep-v5-2-8h20_replay_20260328_220600/chart-deep-v5-2-8h20_replay_100rpm.csv'
    new_csv = f'{BASE}/logs/chart-deep-v5-2-8h20_replay_20260329_130526/chart-deep-v5-2-8h20_replay_100rpm.csv'

    r_old = analyze_csv(old_csv, '旧回放（2026-03-28，--context-length 8192 限制）')
    r_new = analyze_csv(new_csv, '新回放（2026-03-29，无上下文限制）')

    print(f"\n{'='*60}")
    print("  对比摘要")
    print(f"{'='*60}")
    print(f"{'指标':<20} {'旧回放(限制8192)':<20} {'新回放(无限制)':<20} {'变化'}")
    print(f"{'-'*60}")
    print(f"{'总请求数':<20} {r_old['total']:<20} {r_new['total']:<20}")
    print(f"{'成功数':<20} {r_old['ok']:<20} {r_new['ok']:<20}")
    print(f"{'失败数':<20} {r_old['err']:<20} {r_new['err']:<20}")
    print(f"{'成功率':<20} {r_old['rate']:.2f}%{'':<14} {r_new['rate']:.2f}%{'':<14} {r_new['rate']-r_old['rate']:+.2f}%")
    print(f"{'TTFT P90':<20} {r_old['ttft_p90']:.3f}s{'':<13} {r_new['ttft_p90']:.3f}s{'':<13} {r_new['ttft_p90']-r_old['ttft_p90']:+.3f}s")
    print(f"{'TTFS P90':<20} {r_old['ttfs_p90']:.3f}s{'':<13} {r_new['ttfs_p90']:.3f}s{'':<13} {r_new['ttfs_p90']-r_old['ttfs_p90']:+.3f}s")
    print(f"{'E2E P90':<20} {r_old['e2e_p90']:.3f}s{'':<13} {r_new['e2e_p90']:.3f}s{'':<13} {r_new['e2e_p90']-r_old['e2e_p90']:+.3f}s")


if __name__ == '__main__':
    main()
