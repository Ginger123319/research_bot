---
name: llm-deployment-docker
description: Use when deploying an LLM inference service locally via Docker + SGLang — pre-flight VRAM check, TP vs DP recommendation, container startup, health polling, smoke test, and calling llm-service-probing for model capability validation.
---

# LLM Deployment Docker

## Overview

用 Docker 启动 SGLang 推理服务，从预检到验证完整自动化。

**两条执行路径**：
- **路径 A（本机可跑）**：预检通过 → 生成并执行 docker run → 健康检查 → smoke test → 调用 `llm-service-probing` Skill
- **路径 B（显存不足）**：输出推荐命令配置供人工执行，说明显存缺口原因后结束

---

## 步骤 1：预检（Pre-flight）

### 1.1 获取空闲显存

```bash
nvidia-smi --query-gpu=index,name,memory.free --format=csv,noheader,nounits
# 输出示例：
# 0, NVIDIA L20, 46068
# 1, NVIDIA L20, 46068
```

### 1.2 估算模型 VRAM 需求

优先读取 `<model_path>/config.json`：

```python
import json, math

with open(f"{model_path}/config.json") as f:
    cfg = json.load(f)

# 方法A：直接取 num_parameters（部分模型有）
num_params = cfg.get("num_parameters")

# 方法B：从结构估算
if not num_params:
    H = cfg.get("hidden_size", 4096)
    L = cfg.get("num_hidden_layers", 32)
    V = cfg.get("vocab_size", 32000)
    # 粗估：Transformer 主体 ≈ 12 × H² × L，词表 ≈ H × V
    num_params = 12 * H * H * L + H * V

# dtype 字节数（从 torch_dtype 或 config 读取）
dtype_bytes = {"bfloat16": 2, "float16": 2, "int8": 1, "int4": 0.5}.get(
    cfg.get("torch_dtype", "bfloat16"), 2
)

vram_gb_needed = num_params * dtype_bytes / 1e9 * 1.2   # 1.2 为 buffer 系数
```

### 1.3 GPU 拓扑判断 TP vs DP

```bash
nvidia-smi topo -m
```

| 拓扑结果 | 推荐配置 |
|---------|---------|
| 存在 `NV#` 标记（NVLink）| TP（Tensor Parallel）|
| 全部 PIX / SYS（PCIe）| DP（Data Parallel）|

### 1.4 决策

```
可用空闲显存合计(GB) ≥ vram_gb_needed
  → 路径 A：本机部署
  → 推荐 GPU 列表：按空闲显存降序，取前 tp_size 或 dp_size 张

可用空闲显存合计(GB) < vram_gb_needed
  → 路径 B：输出参考命令，说明显存缺口，结束
```

---

## 步骤 2A：部署执行（路径 A）

### 命令模板

```bash
docker run -d \
  --name "<model_basename>-<port>" \
  --gpus "\"device=<gpu_ids>\"" \
  --ipc=host \
  --network=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -v /mnt/ai-llm:/mnt/ai-llm:ro \
  "<image>" \
  python3 -m sglang.launch_server \
    --served-model-name "<model_basename>" \
    --model-path "<model_path>" \
    --host 0.0.0.0 \
    --port <port> \
    --tp-size <tp> \
    --dp-size <dp> \
    --mem-fraction-static 0.85 \
    --context-length 8192 \
    --log-requests \
    --enable-metrics \
    [--chat-template "<model_path>/chat_template.jinja"]   # 仅当文件存在时加入
```

**chat-template 判断**：

```bash
[ -f "${MODEL_PATH}/chat_template.jinja" ] && echo "需要加 --chat-template 参数"
```

### 健康检查轮询

```bash
MAX_WAIT=120   # TP≥4 用 120s；TP=1 用 60s
for i in $(seq 1 $(( MAX_WAIT / 5 ))); do
    sleep 5
    if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
        echo "[OK] 服务就绪，端口: ${PORT}"; break
    fi
    echo "[INFO] 等待中 ${i}/$(( MAX_WAIT / 5 )) ($(( i * 5 ))s)"
done
# 超时处理：
docker logs --tail 50 "${CONTAINER_NAME}"  # 输出末 50 行日志，报错退出
```

### Smoke test

```python
import requests, json

resp = requests.post(
    f"http://localhost:{port}/v1/chat/completions",
    json={"model": model_name, "messages": [{"role": "user", "content": "你好"}],
          "max_tokens": 32},
    timeout=30
)
content = resp.json()["choices"][0]["message"]["content"]
assert content.strip(), "Smoke test 失败：返回内容为空"
print(f"[OK] Smoke test 通过: {content[:50]}")
```

smoke test 通过后 → **调用 `llm-service-probing` Skill**，传入 `server_url` 和 `tokenizer_path`。

---

## 步骤 2B：参考输出（路径 B）

输出以下内容后结束：

```
[INFO] 显存不足，无法在本机部署
  当前空闲显存: X GB（共 N 张 GPU）
  模型估算需求: Y GB（含 1.2x buffer）

[推荐命令] 请在显存充足的机器上执行：
  docker run -d \
    --name "<model>-<port>" \
    --gpus "\"device=0,1,2,3\"" \
    ...（完整命令）

[建议配置]
  GPU 数量: N 张（基于 Y GB 需求）
  TP/DP: <recommendation>（基于 NVLink/PCIe 拓扑）
```

---

## 关键参数速查

| 参数 | 说明 | 典型值 |
|------|------|--------|
| `--tp-size` | Tensor Parallel，NVLink 优先 | 1 / 2 / 4 / 8 |
| `--dp-size` | Data Parallel，PCIe 优先 | 1 / 2 / 4 |
| `--base-gpu-id` | 多容器时 GPU 编号偏移 | 0 / 4 |
| `--mem-fraction-static` | KV cache 静态显存比例 | 0.85 |
| `--context-length` | 最大上下文长度 | 4096 / 8192 |
| `--chat-template` | 非标准 Jinja 模板路径（Qwen 系可省略）| `<model_path>/chat_template.jinja` |
| 健康检查超时 | TP=1: 60s；TP≥4: 120s | — |

---

## 常见报错处理

| 报错关键字 | 原因 | 处理 |
|-----------|------|------|
| `permission denied` | Docker 权限不足 | `sudo usermod -aG docker $USER` 后重新登录 |
| `port is already allocated` | 端口被占用 | `ss -tlnp \| grep <port>` 确认，换端口重试 |
| `CUDA out of memory` / OOM | 显存估算偏低或其他进程占用 | 降低 `--tp-size` 或换空闲 GPU |
| `unauthorized` / `denied` | 镜像 registry 无权限 | `docker login <registry>` 后重试 |
| 健康检查超时 60/120s | 模型加载慢或启动崩溃 | `docker logs --tail 50 <container>` 查原因 |
| `chat_template not found` | 模板路径错误 | 确认 `<model_path>/chat_template.jinja` 是否存在 |

---

## 参考脚本

- `scripts/deploy/start_tianji_querysafety_4b.sh`（TP=4，有 chat_template）
- `scripts/deploy/start_ziwei_32b.sh`（TP=4，标准 Qwen）
- `scripts/deploy/start_ziwei_8b.sh`（TP=1，单卡）

---

## 验证状态

| 模型 | 参数量 | GPU 配置 | 状态 |
|------|--------|---------|------|
| tianji-querysafety-4b-v2-3 | ~3.2B | 4× L20 PCIe, DP=4 TP=1 | ✅ 已验证（2026-03-13）|

**验证结论**：
- 预检：✅ VRAM 估算 ~7.7 GB，GPU 0,1,3,4 各 45+ GB 空闲，路径A正确触发
- 部署：✅ docker run DP=4 成功，65s 健康检查通过
- Smoke test：✅ 0.26s 返回正常响应
- 拓扑判断：✅ PCIe-only → 正确推荐 DP（无 NVLink 标记）
