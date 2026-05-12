---
name: learning-kickstart
description: Use when the user wants to learn, practice, start a study session, or asks what to do today. Triggers on: 想学、开始学、练一下、今天学什么、继续、不知道从哪开始、学习.
---

# Learning Kickstart

## Overview

The user has pre-researched docs in `docs/results/`. Those docs are comprehensive but cause cognitive overwhelm — the user doesn't want to read them. This skill silently uses those docs as background and surfaces only one minimum action per learning track.

**Core principle:** Agent reads docs. User sees only a track table with one action per row.

## Step 1 — Read State + Background (silent, never show user)

1. Read `docs/learning-state.md` if it exists (current track status + last actions)
2. Read the relevant docs in `docs/results/` as background context:
   - `2026-05-06-guitar-learning-guide.md` → guitar track
   - `2026-05-06-ai-era-learning-guide-for-ai-infra-engineer.md` → AI infra track
   - `2026-05-06-learning-effectiveness-system.md` → learning principles
   - `2026-05-06-skinny-weight-gain-weekly-menu.md` → diet/fitness track
   - Any other docs relevant to what user mentions

## Step 2 — Show Track Table Only

Present ONLY this table. No preamble, no explanation:

```
## 现在可以做什么

| 轨道 | 下一步 | 时长 | 完成标准 |
|------|-------|------|---------|
| 🎸 吉他 | [具体动作，如：练 C→G 切换，连续成功 10 次] | 15min | 切换 10 次不卡顿 |
| 💻 AI Infra | [具体动作，如：问 AI 用类比解释 PagedAttention] | 20min | 能用自己的话复述 |
| 🍳 增重饮食 | [具体动作，如：今天午饭额外加 2 个鸡蛋] | 0min | 吃了 |
```

**Extraction rules:**
- Action must be completable in ≤20 minutes
- Must have a clear observable "done" signal
- Must come from the docs — not generic advice
- Guitar: specific chord/exercise from the guide
- AI Infra: one concept via AI dialogue, or one small code task  
- Diet: one single meal/supplement action

User can work any track in any order. Multiple tracks in one day is fine.

## Step 3 — Process Feedback

When user reports completion or skips:

| Report | Next action |
|--------|------------|
| "做了，感觉还行" | Extract next action from docs for that track, mark ✅ |
| "做了，很难" | Simplify next action (smaller chunk), mark 😓 |
| "没做" | Keep same action, mark ⏭️ |
| "做了一半" | Keep same action, mark 🔄 |

After feedback: re-show updated table. Write updated state to `docs/learning-state.md`.

## State File Format (`docs/learning-state.md`)

```markdown
# 学习状态

> 最后更新：YYYY-MM-DD

## 轨道

### 🎸 吉他
- **当前动作**：练 C→G 切换，连续成功 10 次
- **上次状态**：✅ 2026-05-08 完成
- **下一步来源**：guitar-learning-guide.md §和弦切换

### 💻 AI Infra
- **当前动作**：问 AI 用类比解释 PagedAttention
- **上次状态**：⏭️ 跳过
- **下一步来源**：ai-era-learning-guide.md §推理优化

### 🍳 增重饮食
- **当前动作**：今天午饭加 2 个鸡蛋
- **上次状态**：🔄 进行中
- **下一步来源**：skinny-weight-gain-weekly-menu.md §第一周
```

## Key Rules

1. **Never show user the full docs** — docs are agent background only
2. **Never give more than one action per track** — one action = one row
3. **Time estimate must be ≤20 minutes** — if source action is larger, break it down
4. **Always update `docs/learning-state.md` after feedback** — persistence across sessions
5. **If user wants to add a new track** — ask for the topic, check if a doc exists, extract first action

## Common Mistakes

- ❌ Vague action: "学习吉他" → must be "练 C→G 切换 10 次"
- ❌ Showing full doc content to user → causes the exact overwhelm this skill prevents
- ❌ Giving 5 things to do on one track → pick the single most important one
- ❌ Not persisting state → next session starts from zero with no continuity
