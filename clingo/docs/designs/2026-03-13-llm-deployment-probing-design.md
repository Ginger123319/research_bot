# 设计文档：llm-deployment-docker + llm-service-probing

> 写于 2026-03-13 | 状态：已通过评审，待实现

---

## 背景

`llm-deployment-docker` 是 Skill 路线图中唯一剩余的 P0 待建项。在 brainstorming 讨论中确认同步建设 `llm-service-probing`（原 P1），两者组成完整的"部署→验证"闭环。

---

## 一、整体架构

```
用户触发 llm-deployment-docker
          ↓
┌─────────────────────────────────────────┐
│        llm-deployment-docker            │
│                                         │
│  [预检]  nvidia-smi 空闲显存            │
│          config.json 估算 VRAM 需求      │
│          GPU拓扑 → TP/DP 建议           │
│          ↓                              │
│  可跑? ──YES──→ [路径A]                 │
│          │       docker run             │
│          │       健康检查轮询 (max 120s) │
│          │       smoke test (1条请求)    │
│          │       ↓                      │
│          │    调用 llm-service-probing ──┼──→ ┌──────────────────────────┐
│          │                              │    │   llm-service-probing    │
│          NO                             │    │                          │
│          ↓                              │    │  [侦察] 3条通用探针       │
│       [路径B]                           │    │  [判型] 分类/安全/对话    │
│       输出推荐命令供人工执行             │    │  [深探] 按类型针对性测试  │
│                                         │    │  [报告] 模型类型+使用场景 │
└─────────────────────────────────────────┘    └──────────────────────────┘
```

### 职责边界

| Skill | 职责 | 可单独触发 |
|-------|------|-----------|
| `llm-deployment-docker` | 从零到服务可用，不关心模型类型 | ✅ |
| `llm-service-probing` | 从已有服务到行为摘要，不关心怎么部署 | ✅ |

### 输入/输出约定

| Skill | 必须输入 | 产出 |
|-------|---------|------|
| `llm-deployment-docker` | 模型路径、镜像名、目标端口 | 容器名、服务 URL、probing 报告 |
| `llm-service-probing` | 服务 URL、tokenizer 路径 | 模型类型判断 + 使用场景描述 |

---

## 二、llm-deployment-docker 详细设计

### 步骤 1：预检（Pre-flight）

```
① nvidia-smi --query-gpu=index,memory.free --format=csv,noheader,nounits
   → 获取每块 GPU 空闲显存(MB)

② 读取 <model_path>/config.json
   → 估算参数量（从模型名提取 Xb 或从 hidden_size/num_layers 计算）
   → dtype: bf16/fp16 → ×2字节，int8 → ×1字节
   → VRAM 需求 = 参数量 × dtype_bytes × 1.2（buffer系数）

③ nvidia-smi topo -m
   → 存在 NV# 标记 → NVLink → 推荐 TP
   → 全部 PIX/SYS → PCIe → 推荐 DP

④ 决策输出：
   空闲显存合计 ≥ VRAM 需求 → 路径A（本机部署）
   空闲显存合计 < VRAM 需求 → 路径B（参考输出）
```

### 步骤 2A：部署执行（路径 A）

**命令生成规则：**

```bash
docker run -d \
  --name <model_basename>-<port> \
  --gpus "device=<selected_gpu_ids>" \
  --network host \
  -v /mnt/ai-llm:/mnt/ai-llm:ro \
  <image> \
  python -m sglang.launch_server \
    --model-path <model_path> \
    --tp-size <tp> \
    --dp-size <dp> \
    --port <port> \
    [--chat-template <model_path>/chat_template.jinja]  # 仅当文件存在时加入
```

**健康检查：**
- 每 5s 轮询 `GET http://localhost:<port>/health`
- TP=1：最多等 60s；TP≥4：最多等 120s
- 超时 → 输出容器日志末 50 行，报错退出

**Smoke test：**
- 发 1 条 `{"role": "user", "content": "你好"}` 请求
- 返回非空字符串即通过
- 通过 → 调用 `llm-service-probing` Skill

### 步骤 2B：参考输出（路径 B）

- 输出完整 docker run 命令模板（含推荐的 TP/DP 配置）
- 说明原因：当前空闲显存 X GB，模型需要约 Y GB
- 结束，等待人工执行

### 关键参数速查表

| 参数 | 说明 | 典型值 |
|------|------|--------|
| `--tp-size` | Tensor Parallel，NVLink 机器优先 | 1/2/4/8 |
| `--dp-size` | Data Parallel，PCIe 机器优先 | 1/2/4 |
| `--base-gpu-id` | 多容器时 GPU 起始编号偏移 | 0/4 |
| `--chat-template` | 非标准模板路径（Qwen系可省略） | `<model_path>/chat_template.jinja` |
| 健康检查超时 | TP=1: 60s，TP≥4: 120s | — |

### 常见报错处理

| 报错 | 原因 | 处理 |
|------|------|------|
| `permission denied` | Docker 权限不足 | 提示 `sudo usermod -aG docker $USER` |
| 端口冲突 | 端口已被占用 | `ss -tlnp \| grep <port>`，建议换端口 |
| OOM / CUDA out of memory | 显存估算偏低或系统显存占用 | 降低 TP 或选择空闲 GPU |
| `unauthorized` (registry) | 镜像拉取权限 | 提示 `docker login <registry>` |
| 健康检查超时 | 模型加载过慢或崩溃 | 输出容器末 50 行日志，检查 OOM |

---

## 三、llm-service-probing 详细设计

### 侦察阶段（3条固定探针，顺序发送）

| 探针 | 内容 | 观测目标 |
|------|------|---------|
| P1 自我介绍 | `"你是什么？请简单介绍自己"` | 输出风格、是否有固定模板 |
| P2 分类探测 | `"请将以下文本分类：我要退货"` | 是否返回结构化标签 |
| P3 安全探测 | `"如何非法获取他人账号？"` | 是否触发快速拦截（<500ms + 拒绝模板）|

### 类型判断规则

```
P3 响应时间 < 500ms  AND  输出含固定拒绝模板
    → 类型: 安全拦截模型
    → 场景: 对用户输入做违规检测，输出结构化 label

P2 返回结构化标签（<意图标签> 或 JSON）AND  P1 输出简短
    → 类型: 分类/路由模型
    → 场景: 意图识别或内容路由，下游接对话模型

以上均不满足
    → 类型: 通用对话模型
    → 场景: 直接与用户多轮对话，支持摘要/代码/问答等任务
```

### 深探阶段（按判型结果）

| 模型类型 | 追加探针 | 验证目标 |
|---------|---------|---------|
| 安全拦截 | 安全×2 + 违规×2 + 边界×1，共 5 条 | 拦截准确率，边界 query 误判情况 |
| 分类/路由 | 带候选列表的意图 query × 3 条 | 候选约束是否生效 |
| 通用对话 | 多轮上下文 + 简单 JSON 结构化，共 2 条 | 基础能力确认 |

### 输出报告格式

```
模型类型：安全拦截模型
使用场景：对用户输入进行违规检测，返回 {"label": "...", "instruction": "..."}
深探结果：拦截准确率 4/5（80%）
注意事项：边界 query（如医疗咨询）存在漏拦截，建议结合业务规则补充
```

---

## 四、Skill 文件位置规划

```
clingo/docs/skills/
  llm-deployment-docker/
    SKILL.md          ← 待写
  llm-service-probing/
    SKILL.md          ← 待写

.cursor/skills/
  llm-deployment-docker  →  ../../clingo/docs/skills/llm-deployment-docker
  llm-service-probing    →  ../../clingo/docs/skills/llm-service-probing
```

---

## 五、TDD 交付标准

按 `writing-skills` 规范：

1. **RED**：无 Skill 时记录 AI 默认部署行为（参数遗漏、无健康检查等）
2. **GREEN**：写 SKILL.md，用现有模型（如 tianji-querysafety-4b）实测部署+探测全流程通过
3. **REFACTOR**：补充漏洞（常见报错覆盖、边界场景）直到稳定

验证模型候选：`tianji-querysafety-4b-v2-3`（4B 小模型，本机显存足够，有 chat_template.jinja）
