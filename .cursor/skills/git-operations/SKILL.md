---
name: git-operations
description: Use when performing any git operation including branch management, committing, syncing with remote, resolving conflicts, force push, or configuring git identity. Triggers on keywords like git、提交、分支、推送、rebase、合并、冲突、同步.
---

# Git Operations

## Overview

多人协作核心原则：**本地改动永远建立在最新 main 之上，推送前必同步，冲突在本地解决。**

---

## ⚠️ 前置检查（每次 git 操作必做）

**在执行任何 git 操作前，必须先检查本地 user 配置是否存在：**

```bash
git config --list --local | grep user
```

- 若输出包含 `user.name` 和 `user.email` → 继续操作
- 若无输出 → **必须立即配置后再继续**：

```bash
git config user.name "jiangyunfei"
git config user.email "jiangyunfei@cylingo.com"
```

**不能跳过此步骤。** 未配置时提交的 commit 会使用系统默认账号，GitLab 无法正确关联到你的账号。

---

## Quick Reference

### 身份配置（user.name / user.email）

```bash
# 仅当前仓库生效（推荐）
git config user.name "jiangyunfei"
git config user.email "jiangyunfei@cylingo.com"

# 全局生效（所有仓库）
git config --global user.name "jiangyunfei"
git config --global user.email "jiangyunfei@cylingo.com"

# 验证
git config --list --local
```

**关键点：**
- 配置作用范围是「仓库」或「全局」，**与分支无关**
- 切换分支不影响任何 git config 配置
- 配置写入每个 commit 对象，历史已有提交不会改变
- 未配置时 Git 用系统账号名 + hostname 拼默认值，GitLab 无法正确关联账号

---

### Feature Branch + Rebase 工作流

```bash
# 第一步：拉取远程更新（不动本地分支）
git fetch origin

# 查看 origin/main 有多少新提交
git log HEAD..origin/main --oneline

# 第二步：rebase 同步
git rebase origin/main

# 第三步（有冲突时）：解决冲突后继续
git add <冲突文件>
git rebase --continue

# 后悔了，回到 rebase 前
git rebase --abort

# 第四步：安全强制推送
git push origin <分支名> --force-with-lease
```

**Rebase 效果图：**
```
# 前：你的提交 X、Y 建立在旧的 B 上
main:    A - B - C - D
你的分支:  A - B - X - Y

# 后：X'、Y' 接在最新的 D 后面
main:    A - B - C - D
你的分支:        A - B - C - D - X' - Y'
```

---

### 跨分支同步文件

```bash
# 将 jyf 分支的 src/ 目录覆盖到当前分支
git checkout jyf -- src/
git commit -m "sync src/ from jyf branch"
```

---

### 一次性推荐配置

```bash
# 自动记忆冲突解法，下次遇到相同冲突自动解决
git config --global rerere.enabled true
```

---

## 三条铁律

| # | 铁律 | 原因 |
|---|------|------|
| 1 | **推送前必 rebase** | 确保代码建立在最新基础上 |
| 2 | **用 `--force-with-lease` 不用 `--force`** | 防止覆盖别人刚推的代码 |
| 3 | **个人分支 rebase，合进 main 用 MR/PR** | 线性历史 + 代码审查双保险 |

---

## Rebase vs Merge 对比

| | Rebase | Merge |
|---|---|---|
| 历史图 | 一条直线 | 有分叉 + merge commit |
| 可读性 | `git log` 清晰 | 需要 `--graph` 查看 |
| 风险 | 重写 hash，需强制推送 | 无需强制推送 |
| 适合场景 | 个人 feature 分支 | 多人共用分支、受保护分支 |

**分支策略建议：**
- `jyf` / `dev_jyf` 等个人/特性分支 → 用 Rebase
- 合并进 `main` → 走 MR/PR，用 merge 留下合并节点

---

## Common Mistakes

| 错误 | 解决方式 |
|---|---|
| 直接 `git push --force` | 改用 `--force-with-lease`，防覆盖他人提交 |
| 未配置 user.email 就提交 | GitLab 无法关联账号，先 `git config user.email` |
| 误以为切换分支会丢失 config | config 绑定仓库/全局，与分支无关 |
| rebase 冲突解完忘记 `--continue` | `git add` 后必须执行 `git rebase --continue` |
