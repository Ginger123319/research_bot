---
description: 记录每步工作日志到 progress.md，会话结束时汇总写入 project_status.md
alwaysApply: true
---

# Progress Follower

## 每完成一个步骤后

追加写入 `progress.md`，回答以下三个问题（不得遗漏）：

1. 我们实现了哪些功能？
2. 我们遇到了哪些错误？
3. 我们是如何解决这些错误的？

**格式**（每条追加，不覆盖旧记录）：

```
## [YYYY-MM-DD HH:MM] <步骤简述>

### ✅ 实现内容
- ...

### 🐛 遇到的错误
- ...（无则写"无"）

### 🔧 解决方式
- ...（无则写"无"）
```

每 **5 个步骤**提醒一次：是否需要更新 README、运行测试、记录技术债务。

---

## 会话结束时

1. 读取 `progress.md` 全部内容，了解本次会话所有步骤
2. 汇总写入 `project_status.md`（**覆盖**，保留最新一次会话状态）

**`project_status.md` 模板**：

```markdown
# 会话报告 - YYYY-MM-DD

## 📌 会话概览
- **日期**: YYYY-MM-DD
- **主要目标**: ...
- **Git 分支**: ...
- **当前提交**: ...

## ✅ 成果
- ...

## 🔧 文件变更
- ...

## 🐛 问题与解决方案
- ...

## 🎯 技术决策
- ...

## ⚠️ 未完成事项
- ...

## 📈 下次会话计划
- ...
```

---

## 注意事项

- `progress.md`：**追加**，不覆盖，保留完整历史
- `project_status.md`：**覆盖**，只保留最新一次会话的汇总
- 若 `project_status.md` 过长需要归档，手动复制到 `project_status_archive_vol<n>.md` 后清空
