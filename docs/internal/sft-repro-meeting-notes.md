# SFT 复现对齐记录

---

## 源码

- fork 仓库地址 / branch / commit：
- 安装命令：
- 相对官方 main 的改动（模型注册 / Megatron 适配 / 其他）：

---

## 数据

- 数据来源，处理脚本做了什么：
- 文件格式 / 字段名：
- 数据量（train / eval）：
- max_length / 超长处理（截断/丢弃）：
- loss_scale 加权（有/无），配置位置：
- 脱敏样例文件 + schema：已发送 / 路径：

---

## 模型

- 生产模型（122B / 235B，MoE+MLA / Dense）：
- 本地复现推荐小基座：
- 需要手动 register_model（是/否），验证方法：
- HF → Megatron 转换命令 / 脚本：已发送 / 路径：
- 转换后目录结构：
- MLA 权重映射特殊处理（有/无），代码位置：

---

## 训练配置

- 并行度（122B）TP= PP= EP= DP=
- 并行度（235B）TP= PP= EP= DP=
- batch size 计算方法（举例）：
- 完整启动命令：已发送 / 路径：

---

## 监控

- 日志格式 / logging.jsonl 位置：
- 监控工具 / 入口：
- 打出来的指标（PPL / router_aux_loss / expert load）：
- 判断所有 rank 正常进训练循环的方法：
- loss NaN/spike 处理流程 / 历史案例：

---

## Checkpoint

- 目录结构（iter_XXXXXXXX/ 里面）：
- 保存频率 / 保留规则：
- 断点续训命令：
- 不稳定场景 / workaround：

---

## Megatron → HF 转换

- 转换命令 / 脚本：已发送 / 路径：
- 转换后目录结构：
- 转换时机（每个 ckpt / 只转 best）：

---

## 评估

- eval 频率 / 指标：
- 加载格式（HF / Megatron）：
- SFT「有效」的判断标准：
- 自定义测试集验证脚本：已发送 / 路径：
- benchmark 离线测试脚本：已发送 / 路径：
