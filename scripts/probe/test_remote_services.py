#!/usr/bin/env python3
"""
测试 k8s 平台部署的 ziwei 模型服务是否可正常访问
- 8b : https://infer.geniuworks.com/infra-ziwei-intention-twostep-p8b-v1
- 32b: https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1
"""

import json
import time
import urllib.request
import urllib.error

SERVICES = {
    "8b  (ziwei_intention_twostep)": {
        "base_url": "https://infer.geniuworks.com/infra-ziwei-intention-twostep-p8b-v1",
        "model": "ziwei_intention_twostep_8b_v1",
    },
    "32b (xinghan-ziwei)": {
        "base_url": "https://infer.geniuworks.com/infra-xinghan-ziwei-p32b-v1",
        "model": "xinghan-ziwei-32b-v1",
    },
}

TIMEOUT = 30

PASS = "✅ PASS"
FAIL = "❌ FAIL"


def http_post(url: str, payload: dict) -> tuple[int, dict | str]:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:400]
        return e.code, body
    except Exception as e:
        return -1, str(e)


def http_get(url: str) -> tuple[int, dict | str]:
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw.decode(errors="replace") or "(empty body)"
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")[:200]
    except Exception as e:
        return -1, str(e)


def test_service(name: str, base_url: str, model: str) -> bool:
    print(f"\n{'━'*60}")
    print(f"  服务: {name}")
    print(f"  URL : {base_url}")
    print('━'*60)

    all_pass = True

    # ── Case 1: /health ────────────────────────────────────────
    print("\n  [1] GET /health")
    code, body = http_get(f"{base_url}/health")
    ok = (code == 200)
    body_str = str(body).strip() or "(empty body — normal for k8s proxy)"
    print(f"      {PASS if ok else FAIL}  HTTP {code}  →  {body_str[:80]}")
    all_pass = all_pass and ok

    # ── Case 2: /v1/models ────────────────────────────────────
    print("\n  [2] GET /v1/models")
    code, body = http_get(f"{base_url}/v1/models")
    ok = (code == 200)
    if ok and isinstance(body, dict):
        ids = [m.get("id") for m in body.get("data", [])]
        print(f"      {PASS}  HTTP {code}  →  models: {ids}")
    else:
        print(f"      {FAIL if not ok else PASS}  HTTP {code}  →  {str(body)[:120]}")
    all_pass = all_pass and ok

    # ── Case 3: 意图分类（核心功能）───────────────────────────
    test_cases = [
        ("意图分类 - 退货场景",   "我买的手机屏幕碎了，要退货"),
        ("意图分类 - 订单查询",   "帮我查一下我的订单状态"),
        ("意图分类 - 密码找回",   "我忘记密码了登不进去"),
    ]
    for idx, (label, utt) in enumerate(test_cases, start=3):
        print(f"\n  [{idx}] POST /v1/chat/completions  ({label})")
        t0 = time.time()
        code, body = http_post(
            f"{base_url}/v1/chat/completions",
            {
                "model": model,
                "messages": [{"role": "user", "content": utt}],
                "max_tokens": 64,
                "temperature": 0.1,
            },
        )
        elapsed = time.time() - t0
        ok = (code == 200 and isinstance(body, dict))
        if ok:
            content = body["choices"][0]["message"]["content"].strip()
            usage = body.get("usage", {})
            print(f"      {PASS}  HTTP {code}  ({elapsed:.2f}s)")
            print(f"      输入: {utt}")
            print(f"      输出: {content[:120]}")
            print(f"      tokens: prompt={usage.get('prompt_tokens')} "
                  f"completion={usage.get('completion_tokens')}")
        else:
            print(f"      {FAIL}  HTTP {code}  ({elapsed:.2f}s)  →  {str(body)[:200]}")
        all_pass = all_pass and ok

    # ── 汇总 ──────────────────────────────────────────────────
    status = "全部通过 🎉" if all_pass else "存在失败项 ⚠️"
    print(f"\n  ──── 结果: {status} ────")
    return all_pass


def main():
    print("\n" + "═"*60)
    print("  Ziwei 远端 k8s 服务连通性 & 功能测试")
    print("═"*60)

    results = {}
    for name, cfg in SERVICES.items():
        results[name] = test_service(name, cfg["base_url"], cfg["model"])

    print("\n" + "═"*60)
    print("  汇总")
    print("═"*60)
    for name, passed in results.items():
        print(f"  {'✅' if passed else '❌'}  {name}")
    print()


if __name__ == "__main__":
    main()
