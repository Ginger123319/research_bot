#!/usr/bin/env python3
"""
探测 ziwei 系列模型的能力和专属领域
- ziwei_intention_twostep_8b_v1  @ localhost:5291
- xinghan-ziwei-32b-v1           @ localhost:5290
"""

import json
import time
import urllib.request
import urllib.error

# ── 配置 ────────────────────────────────────────────────────────────────────
SERVICES = {
    "8b  (ziwei_intention_twostep_8b_v1)": {
        "base_url": "http://localhost:5291",
        "model": "ziwei_intention_twostep_8b_v1",
    },
    "32b (xinghan-ziwei-32b-v1)": {
        "base_url": "http://localhost:5290",
        "model": "xinghan-ziwei-32b-v1",
    },
}

TIMEOUT = 60  # 每个请求超时秒数


# ── 工具函数 ─────────────────────────────────────────────────────────────────
def chat(base_url: str, model: str, messages: list, max_tokens: int = 512) -> str:
    payload = json.dumps({
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.1,
    }).encode()
    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            data = json.loads(resp.read())
            return data["choices"][0]["message"]["content"].strip()
    except urllib.error.HTTPError as e:
        return f"[HTTP {e.code}] {e.read().decode()[:300]}"
    except Exception as e:
        return f"[ERROR] {e}"


def section(title: str):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print('='*60)


def run_probe(name: str, base_url: str, model: str):
    print(f"\n\n{'#'*70}")
    print(f"# 服务: {name}")
    print(f"# URL : {base_url}  模型: {model}")
    print('#'*70)

    # ── 1. 自我介绍 ─────────────────────────────────────────────────────────
    section("1. 自我介绍 / 功能描述")
    probes_self = [
        "你是什么模型？你能做什么？",
        "请介绍一下你的主要功能和应用场景。",
        "你是专门为哪个领域训练的AI助手？",
    ]
    for q in probes_self:
        print(f"\n  Q: {q}")
        ans = chat(base_url, model, [{"role": "user", "content": q}])
        print(f"  A: {ans[:400]}")

    # ── 2. 意图识别 ──────────────────────────────────────────────────────────
    section("2. 意图识别能力探测")
    intent_prompts = [
        # 通用意图识别
        {
            "label": "用户话语 → 意图分类",
            "messages": [
                {"role": "system", "content": "你是一个意图识别助手，请识别用户话语的意图类别。"},
                {"role": "user", "content": "我想取消我的订单"}
            ]
        },
        {
            "label": "客服场景意图",
            "messages": [
                {"role": "user", "content": "请识别以下用户话语的意图：\n用户：我的快递还没到，已经等了3天了\n意图："}
            ]
        },
        {
            "label": "多意图候选选择",
            "messages": [
                {"role": "user", "content": (
                    "用户说：\"帮我查一下最近的订单\"\n"
                    "候选意图：[查询订单状态, 取消订单, 申请退款, 联系客服]\n"
                    "请选择最匹配的意图："
                )}
            ]
        },
        {
            "label": "两步意图识别（twostep专项）",
            "messages": [
                {"role": "user", "content": (
                    "请用两步法识别用户意图：\n"
                    "第一步：判断对话领域\n"
                    "第二步：识别具体意图\n"
                    "用户话语：\"这个商品质量太差了，我要投诉\""
                )}
            ]
        },
    ]
    for item in intent_prompts:
        print(f"\n  [{item['label']}]")
        ans = chat(base_url, model, item["messages"])
        print(f"  A: {ans[:500]}")

    # ── 3. 结构化输出 ────────────────────────────────────────────────────────
    section("3. 结构化 JSON 输出探测")
    json_prompts = [
        {
            "label": "JSON意图+置信度",
            "messages": [
                {"role": "user", "content": (
                    "分析以下用户话语，以JSON格式输出：意图(intent)、子意图(sub_intent)、置信度(confidence)。\n"
                    "用户话语：\"我要退货，这个手机屏幕有划痕\""
                )}
            ]
        },
        {
            "label": "槽位提取",
            "messages": [
                {"role": "user", "content": (
                    "从以下对话中提取关键槽位，以JSON格式返回：\n"
                    "用户：\"我想订明天下午两点从北京到上海的机票，要商务舱\"\n"
                    "提取槽位（departure_city, destination_city, date, time, cabin_class）："
                )}
            ]
        },
    ]
    for item in json_prompts:
        print(f"\n  [{item['label']}]")
        ans = chat(base_url, model, item["messages"])
        print(f"  A: {ans[:600]}")

    # ── 4. 领域专项测试 ──────────────────────────────────────────────────────
    section("4. 领域专项测试（电商/客服/金融/医疗）")
    domain_prompts = [
        ("电商客服", "用户：我买的口红颜色和图片完全不一样，我要退款"),
        ("金融理财", "用户：我想了解一下余额宝的收益率"),
        ("出行预订", "用户：帮我查一下明天北京到上海的高铁"),
        ("医疗健康", "用户：我最近头疼失眠，应该挂什么科"),
        ("教育咨询", "用户：我孩子今年高考，想了解复旦大学的录取分数线"),
    ]
    for domain, utterance in domain_prompts:
        print(f"\n  [{domain}] {utterance}")
        ans = chat(base_url, model, [
            {"role": "system", "content": "你是一个智能意图识别系统，请识别用户话语的领域和意图。"},
            {"role": "user", "content": utterance}
        ])
        print(f"  A: {ans[:400]}")

    # ── 5. 对话能力 ──────────────────────────────────────────────────────────
    section("5. 多轮对话能力")
    multi_turn = [
        {"role": "user", "content": "我想买一部手机"},
        {"role": "assistant", "content": "好的，请问您有什么预算要求？"},
        {"role": "user", "content": "预算3000左右，要拍照好一点的"},
    ]
    print(f"\n  多轮对话（3轮）：")
    ans = chat(base_url, model, multi_turn)
    print(f"  A: {ans[:400]}")

    # ── 6. 系统提示词响应 ────────────────────────────────────────────────────
    section("6. 系统提示词 + 特定输出格式")
    sys_prompt_test = {
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是一个意图分类器。对用户输入，只需输出以下格式：\n"
                    "DOMAIN: <领域>\nINTENT: <意图>\nSLOTS: <关键槽位>\nCONFIDENCE: <0-1分>"
                )
            },
            {"role": "user", "content": "帮我把这笔转账撤销，我转错人了"}
        ]
    }
    print(f"\n  [固定格式意图输出]")
    ans = chat(base_url, model, sys_prompt_test["messages"])
    print(f"  A: {ans[:500]}")

    print(f"\n{'─'*60}")
    print(f"  ✓ {name} 测试完成")
    print('─'*60)


# ── 主程序 ───────────────────────────────────────────────────────────────────
def main():
    print("\n" + "="*70)
    print("  Ziwei 模型能力探测脚本")
    print("  目标：通过 OpenAI API 接口调用推断模型专属领域和能力")
    print("="*70)

    for name, cfg in SERVICES.items():
        run_probe(name, cfg["base_url"], cfg["model"])
        time.sleep(1)

    print("\n\n" + "="*70)
    print("  全部探测完成！")
    print("="*70)


if __name__ == "__main__":
    main()
