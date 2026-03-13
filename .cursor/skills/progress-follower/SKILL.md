---
description: "在每个已完成步骤的最后，将你的工作日志记录到 @progress.md 文件里 
 包括以下问题并分步回答，且不要遗漏任何信息： 我们实现了哪些功能？ 我们遇到了哪些错误？ 我们是如何解决这些错误的？
 并在本次会话结束时，将你的工作日志记录到 @project_status.md 文件里。 首先查看 @progress.md 文件，了解我们在本次会话中已实现了哪些功能。
 然后写一份详细的会话报告，为下一次工作会话提供上下文"
alwaysApply: true

# 📋 格式规范
format:
  timestamp: "ISO 8601 格式 (YYYY-MM-DD HH:MM:SS)"
  useEmojis: true
  codeHighlight: true
  linkToFiles: true
  linkToCommits: true

# 📊 详细记录维度
includeDetails:
  - 修改的文件列表及行数统计
  - 新增/删除的依赖包
  - 性能指标变化（如果适用）
  - 测试结果（通过/失败的测试数量）
  - 技术决策及理由
  - 遗留问题和技术债务
  - 下一步计划和建议

# 🔍 自动化检查
checks:
  - 确保每次会话都有对应的记录
  - 检查是否遗漏重要的错误信息
  - 验证所有引用的文件路径是否有效
  - 确认是否需要更新 README 或 CHANGELOG

# 📝 上下文信息
contextInfo:
  - 记录当前 Git 分支和提交哈希
  - 记录执行的主要命令
  - 记录相关的 issue 或 PR 编号
  - 记录环境信息（如必要）

# 🏷️ 分类标签
categories:
  feature: "✨ 新功能开发"
  bugfix: "🐛 错误修复"
  refactor: "♻️ 重构"
  docs: "📚 文档更新"
  test: "✅ 测试相关"
  perf: "⚡ 性能优化"
  chore: "🔧 构建/工具链相关"
  style: "💄 代码风格"
  security: "🔒 安全相关"

# 📄 会话总结模板
summaryTemplate: |
  # 会话报告 - {date}
  
  ## 📌 会话概览
  - **开始时间**: {start_time}
  - **结束时间**: {end_time}
  - **总步骤数**: {step_count}
  - **主要目标**: {objectives}
  - **Git 分支**: {branch}
  - **当前提交**: {commit_hash}
  
  ## ✅ 成果
  {achievements}
  
  ## 🔧 文件变更
  {file_changes}
  
  ## 🐛 问题与解决方案
  {issues_and_solutions}
  
  ## 🎯 技术决策
  {technical_decisions}
  
  ## ⚠️ 未完成事项
  {pending_items}
  
  ## 💡 建议与注意事项
  {recommendations}
  
  ## 📈 下次会话计划
  {next_steps}

# 🔗 相关文档
relatedDocs:
  - 自动链接到技术设计文档
  - 自动链接到 API 文档
  - 自动链接到测试报告
  - 自动链接到相关的 issue/PR

# ⏰ 回顾提示
reviewFrequency: 5  # 每5个步骤提醒进行一次小结
reminders:
  - 提示是否需要更新 README
  - 提示是否需要更新 CHANGELOG
  - 提示是否需要运行测试
  - 提示是否需要更新文档
  - 提示是否有技术债务需要记录

# 📊 进度追踪
progressTracking:
  estimateCompletion: true  # 估算任务完成度
  trackTime: true  # 追踪时间消耗
  trackComplexity: true  # 追踪任务复杂度
---