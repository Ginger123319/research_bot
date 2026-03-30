#!/usr/bin/env python3
"""
通用数据处理入口脚本

根据 .env 配置文件中的 DATA_FORMAT 决定处理路径：
  - standard：messages 内联 list（guoxue/ziwei 类型），调用 DataConverter pipeline
  - indexed：messages 是 COS URL（chart 类型），先运行 download_by_indices.py 再转换

用法：
  python scripts/data/process.py --env configs/models/<model>/<tp>.env

设计文档：
  clingo/docs/designs/2026-03-18-generic-benchmark-runner-design.md
"""

import argparse
import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime

PROJECT_DIR = Path(__file__).resolve().parents[2]
SPECFORGE_DIR = Path("/mnt/ai-infra/users/wnd/workspace/repo/SpecForge")
PYTHON = sys.executable


def load_env(env_path: Path) -> dict:
    """解析 bash .env 文件，返回 key→value 字典。"""
    config = {}
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            config[key] = val
    return config


def resolve_path(p: str) -> Path:
    """将相对路径解析为绝对路径（相对 PROJECT_DIR）。"""
    path = Path(p)
    if not path.is_absolute():
        path = PROJECT_DIR / path
    return path


def process_standard(cfg: dict):
    """
    标准模式：messages 内联 list（guoxue/ziwei 格式）
    调用 DataConverter 5 步 pipeline 生成 _all.csv + _poisson_*_stitched.csv
    """
    input_jsonl = resolve_path(cfg["INPUT_JSONL"])
    output_dir = resolve_path(cfg["OUTPUT_DIR"])
    model_name = cfg["MODEL_NAME"]
    model_list = cfg["MODEL_LIST"]
    target_peak_rpm = cfg.get("TARGET_PEAK_RPM", "")

    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"[standard] INPUT_JSONL  = {input_jsonl}")
    print(f"[standard] OUTPUT_DIR   = {output_dir}")
    print(f"[standard] MODEL_LIST   = {model_list}")
    print(f"[standard] PEAK_RPM     = {target_peak_rpm or '（不做峰值采样）'}")
    print()

    if not input_jsonl.exists():
        print(f"❌ 输入文件不存在: {input_jsonl}")
        sys.exit(1)

    # Step 1: 转换 JSONL → _all.csv
    # 使用项目已有的 DataConverter；如有模型专属脚本，可在此路径扩展
    converter_script = PROJECT_DIR / "scripts" / "data" / "converter.py"
    if converter_script.exists():
        print("[Step 1] 调用 DataConverter...")
        result = subprocess.run(
            [PYTHON, str(converter_script),
             "--input", str(input_jsonl),
             "--output-dir", str(output_dir),
             "--model-list", model_list],
            check=False
        )
        if result.returncode != 0:
            print(f"❌ DataConverter 返回错误: {result.returncode}")
            sys.exit(1)
    else:
        print(f"⚠️  未找到通用 converter.py，需手动处理标准格式数据")
        print(f"   期望路径: {converter_script}")
        print("   请参考 scripts/data/process_guoxue_full.py 了解标准处理流程")
        sys.exit(1)

    # Step 2: 峰值采样（仅 DATASET_TYPE=peak 时执行）
    if cfg.get("DATASET_TYPE") == "peak" and target_peak_rpm:
        print(f"\n[Step 2] 峰值采样（目标 RPM={target_peak_rpm}）...")
        all_csv = output_dir / f"{model_name}_all.csv"
        if not all_csv.exists():
            print(f"❌ _all.csv 不存在，无法执行峰值采样: {all_csv}")
            sys.exit(1)
        # 调用插值脚本（路径需根据实际 SpecForge 版本确认）
        interpolator = SPECFORGE_DIR / "scripts" / "poisson_interpolate.py"
        if not interpolator.exists():
            print(f"⚠️  插值脚本不存在: {interpolator}，跳过峰值采样")
        else:
            result = subprocess.run(
                [PYTHON, str(interpolator),
                 "--input", str(all_csv),
                 "--output-dir", str(output_dir),
                 "--target-rpm", target_peak_rpm],
                check=False
            )
            if result.returncode != 0:
                print(f"⚠️  插值脚本返回错误: {result.returncode}，跳过峰值采样")
    else:
        print("\n[Step 2] DATASET_TYPE=all，跳过峰值采样")


def process_indexed(cfg: dict):
    """
    索引模式：messages 是 COS URL（chart 格式）
    Stage 1: download_by_indices.py 下载 raw_content
    Stage 2: 转换 + 过滤 → _all.csv 或 _full.csv

    可选配置项：
      AGENT_MODEL_LIST  逗号分隔的 Agent 模型名称列表（如 "星盘普通"），
                        这些模型的 prompt 将从 role=ib 星盘档案数据重建。
                        不设置时行为与原版完全一致（向下兼容）。
    """
    input_jsonl = resolve_path(cfg["INPUT_JSONL"])
    output_dir = resolve_path(cfg["OUTPUT_DIR"])
    model_name = cfg["MODEL_NAME"]
    model_list_str = cfg["MODEL_LIST"]
    agent_model_list_str = cfg.get("AGENT_MODEL_LIST", "").strip()

    model_list_set = set(s.strip() for s in model_list_str.split(",") if s.strip())
    agent_model_list_set = (
        set(s.strip() for s in agent_model_list_str.split(",") if s.strip())
        if agent_model_list_str else set()
    )
    # 有 Agent 模型时输出到 _full.csv，保留原 _all.csv（直接调用专用）
    output_suffix = "_full" if agent_model_list_set else "_all"

    output_dir.mkdir(parents=True, exist_ok=True)

    download_script = SPECFORGE_DIR / "scripts" / "download_by_indices.py"
    num_workers = int(cfg.get("NUM_WORKERS", "16"))

    # DOWNLOADED_RAW_PATH 可覆盖默认路径（用于复用历史下载文件）
    downloaded_raw_cfg = cfg.get("DOWNLOADED_RAW_PATH", "").strip()
    if downloaded_raw_cfg:
        downloaded_raw = resolve_path(downloaded_raw_cfg)
    else:
        downloaded_raw = output_dir / f"{model_name}_downloaded_raw.jsonl"

    print(f"[indexed] INPUT_JSONL       = {input_jsonl}")
    print(f"[indexed] OUTPUT_DIR        = {output_dir}")
    print(f"[indexed] MODEL_LIST        = {model_list_str}")
    if agent_model_list_set:
        print(f"[indexed] AGENT_MODEL_LIST  = {agent_model_list_str}")
    print(f"[indexed] downloaded_raw    = {downloaded_raw}")
    print(f"[indexed] NUM_WORKERS       = {num_workers}")
    print(f"[indexed] output_suffix     = {output_suffix}")
    print()

    if not input_jsonl.exists():
        print(f"❌ 输入文件不存在: {input_jsonl}")
        sys.exit(1)

    # ── Stage 1: 下载 ────────────────────────────────────────
    if downloaded_raw.exists():
        size_mb = downloaded_raw.stat().st_size / 1024 / 1024
        print(f"[Stage 1] 已存在 {downloaded_raw.name}（{size_mb:.0f} MB），跳过下载")
        print(f"   如需重新下载，请先删除该文件")
    else:
        if not download_script.exists():
            print(f"❌ 下载脚本不存在: {download_script}")
            print("   请确认 SpecForge 仓库路径正确")
            sys.exit(1)
        print(f"[Stage 1] 运行 download_by_indices.py（num_workers={num_workers}）...")
        result = subprocess.run(
            [PYTHON, str(download_script),
             "--input", str(input_jsonl),
             "--output", str(downloaded_raw),
             "--num-workers", str(num_workers)],
            check=False
        )
        if result.returncode != 0:
            print(f"❌ 下载阶段返回错误: {result.returncode}")
            sys.exit(1)
        print(f"✅ 下载完成: {downloaded_raw}")

    # ── Stage 2: 转换 ────────────────────────────────────────
    suffix_desc = f"{output_suffix}.csv"
    print(f"\n[Stage 2] 转换 downloaded_raw.jsonl → {suffix_desc}")
    _convert_indexed_raw(
        downloaded_raw=downloaded_raw,
        output_dir=output_dir,
        model_name=model_name,
        model_list_set=model_list_set,
        agent_model_list_set=agent_model_list_set,
        output_suffix=output_suffix,
    )


def _reconstruct_agent_prompt(data: list, prompt2: dict) -> list | None:
    """
    从 Agent 框架调用记录重建 messages。

    Agent 框架（如 agen1754fc4ce3864211b572f4dc54d3）动态生成 system prompt，
    不持久化到 raw_content，因此 role=a.prompt 为空 []。
    本函数从 role=ib 的星盘档案数据重建与直接调用格式一致的 messages。

    重建路径优先级：
      A. ib.data.data.xingpan.archives.person_self（本人查询，占 84%）
      B. ib.data.data.xingpan.archives.person_1（他人查询，占 16%）
      C. prompt2.profile_info_list（兜底，实测覆盖率 0%）

    返回：
      [{"role": "system", "content": "#UserInfo:..."}, {"role": "user", "content": "..."}]
      或 None（无法重建时）
    """
    import json as _json

    role_ib = next((m for m in data if isinstance(m, dict) and m.get("role") == "ib"), None)
    role_b  = next((m for m in data if isinstance(m, dict) and m.get("role") == "b"),  None)

    user_query = (role_b.get("content") or "").strip() if role_b else ""
    if not user_query:
        return None

    # 提取出生档案数据（三条路径）
    person_data = None
    if role_ib:
        archives = (
            role_ib.get("data", {})
                   .get("data", {})
                   .get("xingpan", {})
                   .get("archives", {})
        )
        person_data = archives.get("person_self") or archives.get("person_1")
    if not person_data:
        person_data = prompt2.get("profile_info_list") or {}

    if not person_data:
        return None

    # 构建 #UserInfo JSON（字段对齐直接调用格式）
    # 注意：用 `or 默认值` 而非 `.get(key, 默认值)`，防止字段存在但值为 None 时 int() 报错
    dt_val = person_data.get("dt") or False
    userinfo = {
        "ST":           int(dt_val) if isinstance(dt_val, bool) else int(dt_val or 0),
        "year":         person_data.get("year"),
        "timezone":     person_data.get("timezone"),
        "sex":          person_data.get("sex"),
        "model_type":   "xinghan-chart-32b-v1-1-agent",
        "use_true_sun": int(person_data.get("use_true_sun") or 0),
        "minute":       person_data.get("minute"),
        "relation":     person_data.get("relation"),
        "month":        person_data.get("month"),
        "hour":         person_data.get("hour"),
        "cx":           person_data.get("cx"),
        "stream":       "true",
        "cy":           person_data.get("cy"),
        "x":            person_data.get("x"),
        "name":         "",   # 直接调用中 name 始终为空字符串
        "y":            person_data.get("y"),
        "id":           person_data.get("itemId") or person_data.get("id") or "",
        "day":          person_data.get("day"),
        "group":        "A",  # 直接调用中 group 固定为 "A"（全量验证确认）
    }

    client_time = prompt2.get("client_time_str", "")
    system_content = (
        "#UserInfo:\n"
        + _json.dumps(userinfo, ensure_ascii=False)
        + "\n#dateStr:\n"
        + client_time
        + "\n#Addition:\n回复格式##结论xxxx##解释"
    )

    return [
        {"role": "system", "content": system_content},
        {"role": "user",   "content": user_query},
    ]


def _convert_indexed_raw(
    downloaded_raw: Path,
    output_dir: Path,
    model_name: str,
    model_list_set: set,
    agent_model_list_set: set | None = None,
    output_suffix: str = "_all",
):
    """将 downloaded_raw.jsonl 转换为 _all.csv（indexed 格式专用）。

    Args:
        agent_model_list_set: 需要通过 role=ib 档案数据重建 prompt 的模型名称集合。
            为 None 或空集合时跳过 Agent 重建路径（向下兼容）。
        output_suffix: 输出文件名后缀（默认 "_all"，Agent 数据合并时可改为 "_full"）。
    """
    import json
    import ast
    import pandas as pd
    from datetime import timezone, timedelta

    TZ_CN = timezone(timedelta(hours=8))
    agent_model_list_set = agent_model_list_set or set()
    all_model_set = model_list_set | agent_model_list_set

    out_csv = output_dir / f"{model_name}{output_suffix}.csv"

    print(f"  输入: {downloaded_raw.name}")
    print(f"  输出: {out_csv.name}")
    print(f"  直接调用模型: {model_list_set}")
    if agent_model_list_set:
        print(f"  Agent 模型:   {agent_model_list_set}（将从 role=ib 档案重建 prompt）")
    print()

    rows = []
    skipped_model = skipped_no_prompt = skipped_bad_json = total_lines = 0
    direct_count = agent_reconstructed = agent_failed = 0

    with open(downloaded_raw, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            total_lines += 1

            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                skipped_bad_json += 1
                continue

            if not isinstance(data, list) or len(data) < 2:
                skipped_bad_json += 1
                continue

            last_a = next(
                (m for m in reversed(data) if isinstance(m, dict) and m.get("role") == "a"),
                None
            )
            if not last_a:
                skipped_no_prompt += 1
                continue

            model = last_a.get("extra_data", {}).get("ai_info", {}).get("model", "")
            if model not in all_model_set:
                skipped_model += 1
                continue

            prompt_val = last_a.get("prompt", "")
            is_agent = model in agent_model_list_set

            if not isinstance(prompt_val, list) or not prompt_val:
                if is_agent:
                    # Agent 框架：prompt 为空，从 role=ib 档案重建
                    p2_str = last_a.get("prompt2", "{}")
                    try:
                        p2 = json.loads(p2_str) if isinstance(p2_str, str) else (p2_str or {})
                    except Exception:
                        p2 = {}
                    prompt_val = _reconstruct_agent_prompt(data, p2)
                    if prompt_val:
                        agent_reconstructed += 1
                    else:
                        agent_failed += 1
                        skipped_no_prompt += 1
                        continue
                else:
                    skipped_no_prompt += 1
                    continue
            else:
                if not is_agent:
                    direct_count += 1

            first_b = next(
                (m for m in data if isinstance(m, dict) and m.get("role") == "b"),
                None
            )
            time_ms = (first_b.get("time") if first_b else None) or last_a.get("time")
            if not time_ms:
                skipped_no_prompt += 1
                continue

            income_dt = (
                datetime.fromtimestamp(int(time_ms) / 1000, tz=TZ_CN)
                .replace(tzinfo=None)
            )

            rows.append({
                "income_time":  income_dt.strftime("%Y-%m-%d %H:%M:%S"),
                "prompt":       "",
                "messages":     json.dumps(prompt_val, ensure_ascii=False),
                "old_response": str(last_a.get("content", "")),
                "user_id":      str(last_a.get("_source_id", "")),
                "line_num":     line_num,
            })

    print(f"  总行数:            {total_lines:,}")
    print(f"  有效行数:          {len(rows):,}")
    print(f"    直接调用:        {direct_count:,}")
    if agent_model_list_set:
        print(f"    Agent 重建成功: {agent_reconstructed:,}")
        print(f"    Agent 重建失败: {agent_failed:,}")
    print(f"  跳过-模型不符:     {skipped_model:,}")
    print(f"  跳过-无prompt:     {skipped_no_prompt:,}")
    print(f"  跳过-JSON错误:     {skipped_bad_json:,}")

    if not rows:
        print("❌ 无有效数据，请检查 downloaded_raw.jsonl 内容和模型别名")
        sys.exit(1)

    # 脏数据过滤（content 为 list）
    def has_list_content(messages_str: str) -> bool:
        if not isinstance(messages_str, str) or not messages_str.strip():
            return False
        try:
            msgs = json.loads(messages_str)
        except Exception:
            try:
                msgs = ast.literal_eval(messages_str)
            except Exception:
                return False
        return any(isinstance(m.get("content"), list) for m in msgs if isinstance(m, dict))

    df = pd.DataFrame(rows)
    df["income_time"] = pd.to_datetime(df["income_time"])
    df = df.sort_values("income_time").reset_index(drop=True)

    before = len(df)
    mask = df["messages"].apply(has_list_content)
    df = df[~mask].reset_index(drop=True)
    removed = before - len(df)
    if removed > 0:
        print(f"\n  脏数据过滤: {before:,} → {len(df):,}（删除 {removed} 行 content=list）")

    # 保存
    df.to_csv(out_csv, index=False)
    size_mb = out_csv.stat().st_size / 1024 / 1024
    print(f"\n✅ 保存完成: {out_csv}  ({size_mb:.1f} MB, {len(df):,} 行)")

    rpm = df["income_time"].dt.floor("min").value_counts()
    print(f"  峰值 RPM: {rpm.max()}")
    print(f"  时间范围: {df['income_time'].min()} ~ {df['income_time'].max()}")

    # 写 README
    _write_readme(output_dir, model_name, model_list_set, agent_model_list_set,
                  output_suffix, total_lines, before, df, rpm)


def _write_readme(output_dir, model_name, model_list_set, agent_model_list_set,
                  output_suffix, total_lines, valid_before, df, rpm):
    readme = output_dir / "README.md"
    out_filename = f"{model_name}{output_suffix}.csv"
    agent_note = ""
    if agent_model_list_set:
        agent_note = f"- Agent 模型（role=ib 档案重建）: `{agent_model_list_set}`\n"
    content = f"""# {model_name} 数据集

## 数据来源

- 直接调用模型（model_list）: `{model_list_set}`
{agent_note}- 处理日期: {datetime.now().strftime('%Y-%m-%d')}
- 处理脚本: `scripts/data/process.py`

## 数据统计

| 项目 | 数量 |
|------|------|
| 下载总行数 | {total_lines:,} |
| 有效行数（过滤前） | {valid_before:,} |
| 最终行数（过滤后） | {len(df):,} |
| 峰值 RPM | {rpm.max()} |
| 时间范围 | {df['income_time'].min()} ~ {df['income_time'].max()} |

## 产出文件

| 文件 | 说明 |
|------|------|
| `{model_name}_downloaded_raw.jsonl` | 下载的原始数据 |
| **`{out_filename}`** | **QPS benchmark 使用此文件** |

## QPS Benchmark 使用

```bash
# 通用脚本（推荐）
nohup bash scripts/benchmark/run_qps_sweep.sh configs/models/{model_name}/8tp.env \\
    > logs/data-pipeline/{model_name}_8tp_qps_$(date +%Y%m%d_%H%M%S).log 2>&1 &
```
"""
    readme.write_text(content, encoding="utf-8")
    print(f"  README: {readme}")


def main():
    from datetime import datetime

    parser = argparse.ArgumentParser(description="通用数据处理入口（支持 standard / indexed 格式）")
    parser.add_argument("--env", required=True, help="配置文件路径，例: configs/models/chart/8tp.env")
    args = parser.parse_args()

    env_path = Path(args.env)
    if not env_path.is_absolute():
        env_path = PROJECT_DIR / env_path
    if not env_path.exists():
        print(f"❌ 配置文件不存在: {env_path}")
        sys.exit(1)

    cfg = load_env(env_path)

    data_format = cfg.get("DATA_FORMAT", "").lower()
    model_name = cfg.get("MODEL_NAME", "?")

    print("=" * 60)
    print(f"通用数据处理  {model_name}")
    print("=" * 60)
    print(f"  配置文件:   {env_path}")
    print(f"  DATA_FORMAT: {data_format}")
    print(f"  开始时间:   {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    if data_format == "standard":
        process_standard(cfg)
    elif data_format == "indexed":
        process_indexed(cfg)
    else:
        print(f"❌ 未知 DATA_FORMAT: '{data_format}'（支持: standard / indexed）")
        sys.exit(1)

    print("\n" + "=" * 60)
    print(f"✅ 数据处理完成")
    print(f"   DATASET_PATH = {cfg.get('DATASET_PATH', '（未配置）')}")
    print("=" * 60)


if __name__ == "__main__":
    main()
