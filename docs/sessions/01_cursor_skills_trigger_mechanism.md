# Cursor Skills 触发机制全解析

**日期**：2026-04-15  
**主题**：`.cursor/skills/` 目录下所有文件的作用分析与触发机制

---

## Skill 触发的底层原理

Cursor Agent 在每次对话启动时，会将所有 Skill 的 **`name` + `description`** 字段预加载到系统 Prompt 中。之后通过两种方式决定是否"读取并执行"某个 Skill：

```
启动时预加载所有 Skill 元数据（name + description）
         ↓
用户发送消息
         ↓
┌─────────────────────────────┐
│  alwaysApply: true？        │──→ 是 → 直接读取 SKILL.md 并执行
└─────────────────────────────┘
         ↓ 否
┌─────────────────────────────┐
│  description 与用户意图匹配？│──→ 是 → 读取 SKILL.md 并执行
└─────────────────────────────┘
         ↓ 否
      不触发，正常对话
```

---

## 项目中三个 Skill 的具体触发条件

### 1. `brainstorming` — 语义匹配触发

```yaml
description: "You MUST use this before any creative work - creating features,
building components, adding functionality, or modifying behavior."
```

**触发词**：创建功能、新增组件、修改行为、做某个需求...

**触发示例**：
- "帮我做一个 XX 功能" → 触发
- "新增一个 API 接口" → 触发
- "修改这个按钮的交互逻辑" → 触发
- "这段代码有个 bug，帮我看看" → **不触发**（不是创意工作）

**触发后的完整行为链**：

```
1. 探索项目上下文（读文件、看 commits）
2. 若涉及视觉问题 → 询问是否开启浏览器可视化伴侣
3. 逐一提问（每次只问一个问题）澄清需求
4. 提出 2-3 个方案 + 权衡 + 推荐
5. 分段展示设计方案，逐段确认
6. 写设计文档 → docs/designs/YYYY-MM-DD-<topic>-design.md → git commit
7. 派发子 Agent 审查 Spec（最多 5 轮）
8. 请用户 review 文档
9. 等待用户指令 → 转入实现阶段
```

> **硬性门控**：步骤 9 之前，绝对不写一行代码。

---

### 2. `progress-follower` — 始终生效（alwaysApply）

```yaml
alwaysApply: true
```

**触发条件**：无条件，每次会话自动生效，无需任何关键词。

**触发后的完整行为链**：

```
每完成一个步骤：
  → 追加写入 progress.md
     ├── 实现了哪些功能
     ├── 遇到了哪些错误
     └── 如何解决的

会话结束时：
  → 读取 progress.md 的全部记录
  → 汇总写入 project_status.md
     ├── 会话概览（时间、目标、Git 分支）
     ├── 成果列表
     ├── 文件变更统计
     ├── 问题与解决方案
     ├── 技术决策
     ├── 未完成事项
     └── 下次会话计划
```

每 5 个步骤还会弹出提醒：是否更新 README、是否跑测试、是否有技术债务。

---

### 3. `writing-skills` — 语义匹配触发

```yaml
description: "Use when creating new skills, editing existing skills,
or verifying skills work before deployment"
```

**触发词**：写 Skill、创建 Skill、修改 Skill、验证 Skill...

**触发示例**：
- "帮我写一个新的 Skill" → 触发
- "这个 SKILL.md 写得好不好" → 触发
- "帮我部署应用" → **不触发**

**触发后的完整行为链**：

```
RED 阶段：
  → 创建 3+ 个压力场景（不加载 Skill 的情况下测试）
  → 跑基线测试，记录 Agent 的失败行为和借口（逐字记录）
GREEN 阶段：
  → 针对实际失败写最小化 Skill（不写多余内容）
  → 带 Skill 重跑场景，验证通过
REFACTOR 阶段：
  → 找新借口 → 加显式否定 → 建反借口表 → 建红旗列表
  → 重测直到"防弹"
```

---

## Skill 文件被读取的时机（渐进式加载）

并非一次性读取全部内容，而是按需加载：

```
阶段一（启动时）：
  仅加载所有 SKILL.md 的 name + description
  → 消耗极少 Token

阶段二（触发时）：
  读取对应 SKILL.md 全文
  → 中等 Token 消耗

阶段三（按需时）：
  读取 SKILL.md 中引用的子文件
  例如：spec-document-reviewer-prompt.md、visual-companion.md
  → 只在真正需要时才加载
```

---

## 存储位置与作用域

| 位置 | 路径 | 作用域 |
|------|------|--------|
| 项目级（本项目） | `.cursor/skills/` | 仅当前项目生效，可提交到 git 共享给团队 |
| 个人级（全局） | `~/.cursor/skills/` | 所有项目都生效，个人私有 |
| 系统内置（只读） | `~/.cursor/skills-cursor/` | Cursor 内置，禁止手动修改 |

本项目的 `brainstorming`、`progress-follower`、`writing-skills` 都在 `.cursor/skills/`，属于**项目级 Skill**，任何使用该仓库的人都会获得这些能力。

---

## 附：`project_status.md` 与归档文件说明

| 文件 | 内容 | 被引用情况 |
|------|------|-----------|
| `project_status.md` | 由 `progress-follower` Skill 在会话结束时写入 | 被 SKILL.md 的 `@project_status.md` 引用 |
| `project_status_archive_vol1.md` | 手动归档的占位文件（当前为空） | 无任何引用，Skill 没有自动归档逻辑 |
| `progress.md` | 由 `progress-follower` Skill 每步追加写入 | 被 SKILL.md 的 `@progress.md` 引用 |
| `progress_archive_vol1.md` | 手动归档的占位文件（当前为空） | 无任何引用 |
