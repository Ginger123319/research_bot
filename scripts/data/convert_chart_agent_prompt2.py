#!/usr/bin/env python3
"""
将 xinghan-chart-32b-v1-1-agent Agent框架调用记录中的 prompt2 转换为 messages。

调用 http://172.21.8.42:1324/v1/chat/completions/messages 接口，
将结构化输入参数还原为实际发往模型的 system + user messages，
并填充到原始记录的 role=a.prompt 字段中。

Input:  datas/xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl
Output: datas/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl
Errors: datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_errors.jsonl

用法:
    python3 scripts/data/convert_chart_agent_prompt2.py
    # 中断后重新执行同一命令即可续传（自动统计 output/error 已写行数）
"""

import json
import time
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ── 路径 ─────────────────────────────────────────────────────────────────────
BASE_DIR    = Path(__file__).resolve().parents[2]
INPUT_FILE  = BASE_DIR / "datas/xinghan-chart-32b-v1-1-agent_calls_raw_260312_260316.jsonl"
OUTPUT_FILE = BASE_DIR / "datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_converted.jsonl"
ERROR_FILE  = BASE_DIR / "datas/output_chart/xinghan-chart-32b-v1-1-agent_calls_errors.jsonl"

# ── 参数 ─────────────────────────────────────────────────────────────────────
API_URL         = "http://172.21.8.42:1324/v1/chat/completions/messages"
CONCURRENCY     = 5
MAX_RETRIES     = 3
RETRY_DELAY     = 2      # 秒，指数退避基数
REQUEST_TIMEOUT = 30     # 秒
REPORT_EVERY    = 200    # 每处理多少条打印进度


# ── API 调用（含重试）────────────────────────────────────────────────────────
def call_api(prompt2_dict: dict) -> tuple:
    """返回 (messages, error_str)，成功时 error 为 None。"""
    last_error = None
    for attempt in range(MAX_RETRIES):
        try:
            resp = requests.post(API_URL, json=prompt2_dict, timeout=REQUEST_TIMEOUT)
            resp.raise_for_status()
            messages = resp.json().get("messages", [])
            if messages:
                return messages, None
            last_error = f"empty messages: {resp.text[:200]}"
        except Exception as e:
            last_error = str(e)
        if attempt < MAX_RETRIES - 1:
            time.sleep(RETRY_DELAY * (2 ** attempt))
    return [], last_error


# ── 单条处理 ─────────────────────────────────────────────────────────────────
def process_line(line_no: int, raw_line: str) -> tuple:
    """返回 (line_no, record_or_None, messages_or_None, error_or_None)。"""
    try:
        record = json.loads(raw_line.strip())
        role_a = record[2]
        prompt2_raw = role_a.get("prompt2", "")
        if not prompt2_raw:
            return line_no, None, None, "missing prompt2"
        prompt2 = json.loads(prompt2_raw) if isinstance(prompt2_raw, str) else prompt2_raw
        messages, error = call_api(prompt2)
        return line_no, record, messages if messages else None, error
    except Exception as e:
        return line_no, None, None, str(e)


# ── 工具函数 ─────────────────────────────────────────────────────────────────
def count_lines(path: Path) -> int:
    if not path.exists():
        return 0
    with open(path) as f:
        return sum(1 for _ in f)


# ── 主流程 ───────────────────────────────────────────────────────────────────
def main():
    total   = count_lines(INPUT_FILE)
    success = count_lines(OUTPUT_FILE)
    errors  = count_lines(ERROR_FILE)
    skip    = success + errors

    print(f"输入: {INPUT_FILE.name}")
    print(f"总行数: {total:,}")
    if skip > 0:
        print(f"续传: 跳过前 {skip:,} 条 (已成功={success:,} 已错误={errors:,})")
    else:
        print("全新启动")
    print(f"并发: {CONCURRENCY}  最大重试: {MAX_RETRIES}  超时: {REQUEST_TIMEOUT}s")
    print()

    t_start      = time.time()
    next_report  = skip + REPORT_EVERY
    # 有序写出：buffer 缓存已完成但尚未写出的结果，write_ptr 追踪下一个待写行号
    buffer: dict = {}
    write_ptr    = skip

    with open(INPUT_FILE, encoding="utf-8") as fin, \
         open(OUTPUT_FILE, "a", encoding="utf-8") as fout, \
         open(ERROR_FILE,  "a", encoding="utf-8") as ferr:

        # 跳过已处理行
        for _ in range(skip):
            fin.readline()

        def flush_buffer():
            """按序将 buffer 中连续已就绪的结果写出。"""
            nonlocal write_ptr, success, errors
            while write_ptr in buffer:
                record, messages, error = buffer.pop(write_ptr)
                if messages is not None and record is not None:
                    record[2]["prompt"] = messages
                    fout.write(json.dumps(record, ensure_ascii=False) + "\n")
                    success += 1
                else:
                    ferr.write(json.dumps(
                        {"line_no": write_ptr, "error": error},
                        ensure_ascii=False
                    ) + "\n")
                    errors += 1
                write_ptr += 1
            fout.flush()
            ferr.flush()

        # 将剩余所有行提交给线程池（Future 对象本身很轻量）
        with ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
            future_to_lineno: dict = {}
            for i, line in enumerate(fin):
                ln = skip + i
                fut = pool.submit(process_line, ln, line)
                future_to_lineno[fut] = ln

            for fut in as_completed(future_to_lineno):
                ln, record, messages, error = fut.result()
                buffer[ln] = (record, messages, error)
                flush_buffer()

                total_done = success + errors
                if total_done >= next_report:
                    elapsed = time.time() - t_start
                    new_done = total_done - skip
                    rate = new_done / elapsed if elapsed > 0 else 0
                    eta  = (total - total_done) / rate if rate > 0 else float("inf")
                    print(
                        f"  [{time.strftime('%H:%M:%S')}] "
                        f"{total_done:>6,}/{total:,} ({total_done/total*100:.1f}%) | "
                        f"成功={success:,} 错误={errors:,} | "
                        f"速率={rate:.2f}条/s 剩余≈{eta/3600:.1f}h",
                        flush=True
                    )
                    next_report = total_done + REPORT_EVERY

    total_done = success + errors
    elapsed = time.time() - t_start
    print()
    print("═" * 60)
    print(f"完成！总处理={total_done:,}/{total:,}  成功={success:,}  错误={errors:,}")
    print(f"总耗时: {elapsed/3600:.2f}h ({elapsed:.0f}s)")
    print(f"输出:   {OUTPUT_FILE}")
    if errors > 0:
        print(f"错误日志: {ERROR_FILE}")


if __name__ == "__main__":
    main()
