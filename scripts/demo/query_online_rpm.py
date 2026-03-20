#!/usr/bin/env python3
"""
Demo: 从 VictoriaMetrics（Grafana 数据源）查询线上模型的每日最大 RPM

用途：
  给定一个已部署模型的 Kubernetes 部署名（如 tianji-querysafety-p4b-v23-tp4），
  查出它在线上实际承载的流量峰值，并与评测结论做对比。

使用方式：
  python3 scripts/demo/query_online_rpm.py <部署名> [--days N] [--instances N] [--sla-rpm N]

示例：
  python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4
  python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4 --days 7 --instances 8 --sla-rpm 480
  python3 scripts/demo/query_online_rpm.py lingyu-p235b-a22b-v9-final --instances 10 --sla-rpm 180
"""

import argparse
import datetime
import json
import sys
import time
import urllib.parse
import urllib.request

# ── 配置 ─────────────────────────────────────────────────────────────────────

VM_BASE = "http://172.21.52.62:8481/select/0/prometheus"

# SGLang 指标名有两种格式（旧版用冒号，新版用下划线），两种都尝试
SGLANG_METRICS = [
    "sglang_num_requests_total",   # 新版 SGLang（0.4+）
    "sglang:num_requests_total",   # 旧版 SGLang（recording rule 格式）
]

TZ_CST = datetime.timezone(datetime.timedelta(hours=8))

# ── VictoriaMetrics 查询函数 ──────────────────────────────────────────────────

def vm_instant(promql: str) -> list:
    """即时查询（当前时刻的值），返回 result 列表，失败返回 []。"""
    url = VM_BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": promql})
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read())
        if data.get("status") == "success":
            return data["data"]["result"]
    except Exception as e:
        print(f"  [warn] instant query 失败: {e}", file=sys.stderr)
    return []


def vm_range(promql: str, start: int, end: int, step: int) -> list:
    """范围查询，返回 result 列表，失败返回 []。"""
    url = VM_BASE + "/api/v1/query_range?" + urllib.parse.urlencode({
        "query": promql,
        "start": str(start),
        "end": str(end),
        "step": str(step),
    })
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
        if data.get("status") == "success":
            return data["data"]["result"]
    except Exception as e:
        print(f"  [warn] range query 失败: {e}", file=sys.stderr)
    return []


# ── 核心查询逻辑 ──────────────────────────────────────────────────────────────

def query_rpm(deployment: str, days: int = 7):
    """
    查询指定部署的 RPM 数据。

    参数
    ----
    deployment : str
        Kubernetes 部署名，对应 VictoriaMetrics label
        nexus_aiinfra_cece_com_name 的值，例如：
          - tianji-querysafety-p4b-v23-tp4
          - lingyu-p235b-a22b-v9-final
    days : int
        查询最近 N 天的数据（默认 7 天）

    返回
    ----
    dict，包含：
        current_rpm   : float | None  当前 1 分钟滑窗 RPM
        daily_max_7d  : float | None  N 天内的峰值 RPM
        daily         : list[dict]    每天的峰值 RPM，格式 [{"date": "2026-03-20", "max_rpm": 739.0}]
        metric_used   : str           实际命中的指标名
    """
    label = f'nexus_aiinfra_cece_com_name="{deployment}"'
    now_ts = int(time.time())
    start_ts = now_ts - days * 86400

    # 1. 检测哪种指标格式存在，并获取当前 RPM
    current_rpm = None
    metric_used = None

    for metric in SGLANG_METRICS:
        res = vm_instant(f'sum(rate({metric}{{{label}}}[1m])) * 60')
        if res:
            current_rpm = float(res[0]["value"][1])
            metric_used = metric
            break

    # 如果服务当前不活跃，用历史范围查询确定指标格式
    if metric_used is None:
        for metric in SGLANG_METRICS:
            probe = vm_range(
                f'max_over_time(sum(rate({metric}{{{label}}}[1m]))[24h:1m]) * 60',
                start_ts, now_ts, 86400,
            )
            if probe:
                metric_used = metric
                break

    if metric_used is None:
        return {
            "current_rpm": None,
            "daily_max_7d": None,
            "daily": [],
            "metric_used": None,
            "error": f"未找到部署 '{deployment}' 的 SGLang 指标，请确认部署名正确",
        }

    # 2. 查询 N 天内每天的最大 RPM（step=1d，滑窗=1d）
    range_res = vm_range(
        f'max_over_time(sum(rate({metric_used}{{{label}}}[1m]))[24h:1m]) * 60',
        start_ts, now_ts, 86400,
    )

    daily = []
    if range_res:
        for ts, val in range_res[0].get("values", []):
            dt = datetime.datetime.fromtimestamp(ts, tz=TZ_CST).strftime("%Y-%m-%d")
            daily.append({"date": dt, "max_rpm": round(float(val), 1)})

    daily_nonzero = [d for d in daily if d["max_rpm"] > 0]
    daily_max = max((d["max_rpm"] for d in daily_nonzero), default=None)

    return {
        "current_rpm": round(current_rpm, 1) if current_rpm is not None else None,
        "daily_max_7d": daily_max,
        "daily": daily,
        "metric_used": metric_used,
    }


# ── 打印报告 ──────────────────────────────────────────────────────────────────

def print_report(deployment: str, result: dict, instances: int, sla_rpm: float):
    BOLD  = "\033[1m"
    GREEN = "\033[32m"
    YELLOW= "\033[33m"
    RED   = "\033[31m"
    RESET = "\033[0m"
    CYAN  = "\033[36m"

    print()
    print(f"{BOLD}{'─' * 56}{RESET}")
    print(f"{BOLD}  在线承载量报告 — {deployment}{RESET}")
    print(f"{'─' * 56}")

    if result.get("error"):
        print(f"  {RED}❌ {result['error']}{RESET}")
        print()
        return

    cur  = result["current_rpm"]
    peak = result["daily_max_7d"]
    days_data = [d for d in result["daily"] if d["max_rpm"] > 0]

    cur_str  = f"{cur:.0f} RPM"  if cur  is not None else "—"
    peak_str = f"{peak:.0f} RPM" if peak is not None else "—"

    print(f"  {CYAN}指标格式{RESET}   : {result['metric_used']}")
    print(f"  {CYAN}当前实时{RESET}   : {BOLD}{cur_str}{RESET}")
    print(f"  {CYAN}7日峰值{RESET}    : {BOLD}{peak_str}{RESET}")

    # 对比评测 SLA
    if sla_rpm > 0 and peak is not None:
        total_sla = sla_rpm * instances
        usage_pct = peak / total_sla * 100
        if usage_pct > 100:
            color = RED
            badge = "⚠️  超出总容量"
        elif usage_pct > 80:
            color = YELLOW
            badge = "⚡ 接近上限"
        else:
            color = GREEN
            badge = "✅ 容量充足"

        inst_str = (f"{sla_rpm:.0f} RPM × {instances} 实例 = {total_sla:.0f} RPM"
                    if instances > 1 else f"{sla_rpm:.0f} RPM")
        print(f"  {CYAN}评测 SLA{RESET}   : {inst_str}")
        print(f"  {CYAN}容量使用率{RESET} : {color}{BOLD}{usage_pct:.1f}%{RESET}  {badge}")

    # 每日峰值明细
    if days_data:
        print(f"\n  {'日期':<12} {'峰值 RPM':>10}")
        print(f"  {'─' * 24}")
        for row in reversed(days_data):
            bar_len = int(row["max_rpm"] / max(d["max_rpm"] for d in days_data) * 20)
            bar = "█" * bar_len
            print(f"  {row['date']:<12} {row['max_rpm']:>8.0f}   {CYAN}{bar}{RESET}")

    print(f"{'─' * 56}")
    print()


# ── CLI 入口 ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="查询线上模型每日最大 RPM（从 VictoriaMetrics 拉取）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例：
  # 只看数据，不做 SLA 对比
  python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4

  # 带 SLA 对比（8 实例，单实例 480 RPM）
  python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4 \\
    --instances 8 --sla-rpm 480

  # lingyu，查最近 14 天
  python3 scripts/demo/query_online_rpm.py lingyu-p235b-a22b-v9-final \\
    --days 14 --instances 10 --sla-rpm 180

  # 输出原始 JSON（便于脚本集成）
  python3 scripts/demo/query_online_rpm.py tianji-querysafety-p4b-v23-tp4 --json
        """,
    )
    parser.add_argument("deployment", help="部署名，即 K8s LWS 名称，如 tianji-querysafety-p4b-v23-tp4")
    parser.add_argument("--days",      type=int,   default=7,   help="查询最近 N 天（默认 7）")
    parser.add_argument("--instances", type=int,   default=1,   help="当前部署实例数（默认 1）")
    parser.add_argument("--sla-rpm",   type=float, default=0.0, help="单实例评测 SLA RPM 上限（默认不做对比）")
    parser.add_argument("--json",      action="store_true",     help="输出原始 JSON，不打印报告")
    args = parser.parse_args()

    result = query_rpm(args.deployment, days=args.days)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print_report(args.deployment, result, args.instances, args.sla_rpm)


if __name__ == "__main__":
    main()
