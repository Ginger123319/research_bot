# AI-Infra 操作启发式（个人沉淀）

> 沉淀位置：`docs/internal/infra-heuristics.md`
> 起始日期：2026-05-28
> 维护者：江云飞

---

## 这是什么

这是一份**离开公司也带得走的"基础设施直觉"**资产清单。每条启发式都是一个**可调用的判断规则**——未来遇到类似场景，能直接拿出来用，不用从头思考。

**对应到 [career-playbook 手册](./2026-05-28-ai-era-work-and-career-playbook.md)**：
- 1.3 节「间接相关 + < 10 分钟 + 能写启发式」的处理路径——产物就是写到这里
- 3.3.1 节「系统思维」「问题定义」等可迁移能力——这是它们的具体载体
- 5.2 节每周硬动作「至少沉淀 1 条新启发式」——这里就是落地的地方

---

## 怎么用

**写的时候**：
1. 触发场景必须是「未来真的会遇到」的，不是想象的
2. 第一反应要**具体到一个动作**，不是抽象的原则
3. 例外/反例不能少——只有正面规则没有边界的启发式都是空话
4. 每条都标注**沉淀日期**、**来源**（哪个问题让我想清楚的）、**来源类型**（见下）

**用的时候**：
1. 遇到新场景，先查索引，看有没有现成启发式可调用
2. 调用时如果发现"启发式没覆盖这个变种" → **当场补充**到原启发式的"例外"里
3. 每月翻一遍，删掉不再有效的，强化反复用到的

**反模式**（要警觉）：
- 写得太抽象：「要谨慎」「要思考清楚」——这种等于没写
- 一条规则下面没有例外：现实里没有"绝对正确"的启发式
- 收藏后从不调用：每月要做一次"过去 30 天用了哪几条"的复盘

---

## 来源类型（防止"知道分子"退化）

每条启发式都要打一个**来源类型标签**。原因：来源决定了它的可信度和扎实度——「在对话里听过」≠「自己踩过」≠「读过论文」。

| 标签 | 含义 | 可信度 | 备注 |
|------|------|-------|------|
| `[real-incident]` | 真实踩坑沉淀（生产/工作中真的发生过） | 🔥 最高 | 身体记忆，最难忘 |
| `[experiment]` | 主动做实验 / POC 验证得到 | 🔬 高 | 自己验证过的事实 |
| `[codebase]` | 读源码或一手实现读出来的 | 📚 高 | 一手资料 |
| `[paper]` | 论文 / 官方文档 / 架构白皮书 | 📖 中 | 权威但需在自己场景里验证 |
| `[mentor]` | 资深同事 / 导师指点 | 👥 中 | 别人的经验，要本地化检验 |
| `[conversation]` | 和 AI / 同事的对话讨论 | 💬 较低 | 容易停留在"知道"层，**待升级** |

**每月复盘的硬规则**：

> 如果 `[conversation]` 类型的启发式占比 > 50%，说明我在变成「读启发式的人」而不是「产出启发式的工程师」。
> 这时要主动去**真实场景验证 / 做实验**，把高占比的 `[conversation]` 启发式升级到 `[experiment]` 或 `[real-incident]`。

**升级机制**：

每条启发式可以经历来源升级，如：
- 初次写入时：`[conversation]` —— 在和 AI 讨论时想清楚的
- 一个月后真的用上了：升级为 `[real-incident]`，并加一行 "**首次实战调用**：YYYY-MM-DD，结果：xxx"
- 升级日期一并保留——这样能看到这条启发式的"成熟轨迹"

---

## 索引

来源类型用 emoji 标识：🔥 real-incident / 🔬 experiment / 📚 codebase / 📖 paper / 👥 mentor / 💬 conversation

| ID | 主题 | 触发场景 | 来源 | 沉淀日期 | 首次实战 |
|----|------|---------|------|---------|---------|
| [H-001](#h-001-docker-容器破坏性操作的判断) | Docker 容器破坏性操作的判断 | 看到容器内有 rm -rf 之类命令 | 💬 conversation | 2026-05-28 | — |
| [H-002](#h-002-bind-mount-的边界单点穿透原则) | Bind Mount 的边界（单点穿透原则） | 设计/review docker run 的 -v 挂载 | 💬 conversation | 2026-05-28 | — |
| [H-003](#h-003-给-ai-agent-自动执行命令的最小安全沙箱) | 给 AI Agent 自动执行命令的最小安全沙箱 | 准备放开手让 AI 自动执行命令 | 💬 conversation | 2026-05-28 | — |

---

## H-001 Docker 容器破坏性操作的判断

**触发场景**：看到（或听说）容器内执行了破坏性命令——`rm -rf /` / 误操作 / 同事报告"容器挂了不知道宿主机有没有事"

**第一反应**（一个具体动作）：

> **先跑 `docker inspect <container> | jq '.[].Mounts'`，看 `-v` 挂载列表——不要先恐慌、不要先重启。**

**完整判断顺序**：

```
1. 有 -v 挂载真实数据目录吗？
   ├── 没有                → 重启容器即可，宿主机 OK
   └── 有                  → 看挂载点下是什么
       ├── 真实业务数据 (models / data / logs / 用户目录)
       │       → 紧急：先停止容器（防止继续删），
       │         再评估损失，必要时从快照/备份恢复
       └── 只是工作目录 (临时输出 / 编译产物)
               → 重启容器即可

2. 是 --privileged 模式吗？
   └── 是 + 配合 mount      → 风险叠加，可能突破隔离
                            → 立刻评估是否影响宿主机其他服务

3. 容器跑的是核心服务吗？影响多少在线流量？
   └── 如果是              → 走故障应急流程，而不是技术分析流程

4. 是否挂载了 docker.sock？
   └── 是                  → docker 控制可能断了，但宿主机文件不受影响
                            → 重启 docker daemon 或重建容器
```

**例外 / 反例**：
- 如果容器是 `--network host` 模式：网络层和 host 共享，但**文件系统仍然隔离**，不要被网络模式误导
- 如果容器内进程是 root 且做了 `chroot`/`pivot_root` 之外的奇怪操作：理论上能影响 host，但需要明确的提权步骤——默认情况下不用担心
- 如果 host 是某些极端老的 Linux 内核（< 3.18）：cgroup/namespace 隔离可能有 bug——但在现代环境（Ubuntu 22.04+）这不是问题

**给自己的操作纪律**：
- 任何"容器内疑似破坏性操作"的告警 → **第一动作永远是 `docker inspect` 看挂载**，不是 ssh 上去看 host
- 写 docker run 命令时，**写完先 dry-run review 挂载列表**——挂载点决定爆炸半径

**来源**：💬 `[conversation]` — 2026-05-28 和 Claude 的对话，问题"docker 容器中如果将 / 目录删除，对于服务器有什么影响？"

**首次实战调用**：— （待发生，发生后回填日期 + 结果，并把来源升级为 `[real-incident]`）

---

## H-002 Bind Mount 的边界（单点穿透原则）

**触发场景**：设计 docker run 命令的 `-v` 挂载；review 别人的 docker run；评估容器逃逸/数据泄露风险

**核心事实**（一句话能记住的）：

> **Bind mount 是「单点穿透」，不是「路径穿透」。**
> **挂载点这一个目录在容器和 host 之间打通，但挂载点的父/兄弟目录对容器完全不可见。**

**容器视角 vs Host 视角对照**：

| 容器内路径/操作 | 实际效果 | Host 文件系统 |
|---------------|---------|--------------|
| `/workspace/foo` 修改 | ✅ 真改 | host 的 `/mnt/ai-infra/users/jyf/foo` 也变 |
| `/workspace/*` 删除 | ✅ 真删 | host 的 `/mnt/ai-infra/users/jyf/` 下文件**全没** |
| `/workspace/..` cd 进去 | ✅ 能进 | 但进的是**容器自己的 rootfs 根**，不是 host 的 `/mnt/ai-infra/users/` |
| 容器视角的 `/` rm -rf | ✅ 能删 | 容器自己挂掉，**host 完全不受影响** |
| `/mnt/ai-infra/users/` 访问 | ❌ 路径不存在 | host 这个路径在容器里**根本看不见** |
| `/mnt/ai-infra/users/alice/`（兄弟目录）访问 | ❌ 路径不存在 | 同上，看不见 |

**结论**：挂载粒度 = 容器能影响 host 的最大半径。挂得越精确，爆炸半径越小。

**3 个会破坏单点穿透的例外**：

| 反模式 | 例子 | 风险 |
|-------|------|------|
| **挂载粒度过粗** | `-v /mnt/ai-infra/users:/workspace` | 容器能毁掉**所有同事**的数据，权限放大 |
| **挂了 host 根或上层** | `-v /:/host` 或 `-v /mnt:/mnt` | 容器能毁掉**整个 host** |
| **`--privileged` + 容器内手动 mount** | 容器有 `CAP_SYS_ADMIN`，可以在容器里 `mount` host 的任意目录 | 完全突破挂载边界 |

**几个容易混淆的细节**：
- **Symlink 攻击**：如果挂载目录下有 `link -> /etc`，容器内通过这个 symlink 访问 host 的 /etc 吗？**默认不能**——symlink 解析发生在容器内，受 mount namespace 限制
- **Hardlink**：如果攻击者能在 host 上预先做好 hardlink 到敏感文件，再让容器写入——这是一个真实的攻击面，但需要 host 上的写权限作为前提
- **删除挂载点本身**：容器内 `rm -rf /workspace` 或 `rmdir /workspace`——**通常失败**（device busy），因为 mount 占着 inode。容器内一般没权限 umount 自己的挂载点

**给自己的操作纪律**：

启动容器时：
- ✅ **挂载粒度精确到用户级或更细**：`-v /mnt/ai-infra/users/jyf:/workspace` ✅
- ❌ 绝不挂上层：`-v /mnt/ai-infra:/data` ❌（挂了整个 AI-Infra 卷）
- ❌ 绝不挂 host 根：`-v /:/host` ❌（除非有不可替代的运维场景且明确知道风险）
- ⚠ `--privileged` 只在必要时用，且永远不和宽挂载组合

Review 别人的 docker run 时：
- **第一眼看 `-v` 列表**——挂载粒度决定爆炸半径
- 如果挂了上层目录，问对方"为什么不能挂得更精确"——大概率没必要
- 如果同时有 `--privileged` 和数据卷挂载，警觉度拉满

写 `docker-compose.yml` 或 K8s `volumeMounts` 时：
- 同样的纪律——`volumeMounts` 的 `mountPath` 和 `subPath` 设计要让最小权限原则成立
- K8s 里可以用 `subPath` 在同一个 PVC 里给不同 pod 挂不同子目录，避免"粒度过粗"

**来源**：💬 `[conversation]` — 2026-05-28 和 Claude 的对话，追问"挂载了 `/mnt/ai-infra/users/`，能否影响上一级目录？"

**首次实战调用**：— （待发生，发生后回填日期 + 结果，并把来源升级为 `[real-incident]`）

---

## H-003 给 AI Agent 自动执行命令的最小安全沙箱

**触发场景**：要放开手让 AI（Claude / Cursor / Codex / 任何 agent）自动执行命令——不再每条都人工确认，让它在一个环境里连续跑

**第一反应**（一个具体动作）：

> **永远不要让 AI 在 host 上裸跑——哪怕"觉得指令安全"。**
> **用 docker 包一层 + 下面 6 个最小配置，缺一个都不算沙箱。**

**6 个必配项**（少一个就不是沙箱，是裸跑套了个皮）：

| # | 配置 | 防什么 |
|---|------|-------|
| 1 | `--network=none`（默认断网，需要联网时再开白名单） | AI 把代码/数据偷偷传到外网 |
| 2 | `--memory=Xg --cpus=N --pids-limit=512` | fork 炸弹 / 占满资源 |
| 3 | `--user $(id -u):$(id -g)`（用 host 的 UID 跑） | 容器内 root → host 上 root owned 文件难清 |
| 4 | `--security-opt=no-new-privileges` + `--cap-drop=ALL` | 容器内提权 |
| 5 | `--read-only` + `--tmpfs /tmp` | 容器自己的 rootfs 只读，AI 没法污染容器其他位置 |
| 6 | `-v /mnt/ai-infra/users/jyf/<this-project>:/workspace`（精确到子项目） | H-002 单点穿透原则——爆炸半径最小化 |

**完整命令模板**：

```bash
docker run --rm \
  --network=none \
  --memory=4g --cpus=2 --pids-limit=512 \
  --user $(id -u):$(id -g) \
  --security-opt=no-new-privileges \
  --cap-drop=ALL \
  --read-only --tmpfs /tmp:size=512m \
  -v /mnt/ai-infra/users/jyf/<this-project>:/workspace \
  -w /workspace \
  <agent-image> bash
```

**外层防线**（光容器配置不够）：

1. **工作目录必须有 git 或 snapshot**——容器内 `rm -rf /workspace/*` 是真删的，git commit 是最便宜的"还原点"
2. **永远不要把生产 credential 注入 AI 容器**——`.env` / `~/.aws/credentials` / `~/.ssh/*` / 任何 `-e API_KEY=xxx` 都不行
3. **AI 想联网时再单开**——`--network=custom-net` + 出口白名单（egress filter），而不是回到 `--network=host`

**例外 / 反例**（看到这些立刻知道沙箱破了）：

| 反模式 | 后果 |
|--------|-----|
| `--privileged` | 等于裸跑，**直接放弃沙箱** |
| 挂 `/var/run/docker.sock` | AI 能控制 host docker daemon，从沙箱里 spawn 其他容器 |
| 挂 `/` 或 `/home` 或用户根目录 | H-002 反例，爆炸半径 = 整个 host / 整个用户所有项目 |
| 挂载点是用户根目录而不是子项目 | 一次失误删光所有项目，而不是一个 |
| 容器内有 sudo + 容器是 root | AI 能改 /workspace 下文件的 owner，host 上后续清不掉 |
| 把 `OPENAI_API_KEY` 这类用 `-e` 注入 | AI 读到 env，能把 key 上传到外网（即便 --network=none 也可能通过 /workspace 落盘泄露） |

**升级路径**（什么时候要超越 docker）：

| 场景 | 用什么 |
|------|-------|
| 个人开发场景（受控的 Claude/Cursor） | docker + 上面 6 个配置 ✅ 足够 |
| 给完全不受控的 AI（外部下载的 agent / 不信任的代码）跑 | 上 microVM：[E2B](https://e2b.dev) / [Daytona](https://www.daytona.io/) / 自己跑 Firecracker |
| 多租户隔离 / 给客户用 | K8s + gVisor / Kata Container |
| 极端情况（敌对代码） | 物理隔离的机器或专用 jump host |

**给自己的操作纪律**：

- 启动新 AI agent 环境时，**必须对照 6 项 checklist**——不能凭直觉省略
- review 别人的 AI agent 启动脚本（同事的 / GitHub 上的 / 教程里的）时：**先扫一眼有没有 `--privileged` 和 `docker.sock`**——这两个一出现立刻拒绝
- 把这套 docker run 模板存成 `scripts/ai-sandbox.sh`，每次启动就 source 它，**不要每次手敲 docker run**
- 工作目录变更前，习惯性 `git status && git stash || git commit -am "wip: before ai run"`——把"还原点"做成肌肉记忆

**来源**：💬 `[conversation]` — 2026-05-28 和 Claude 的对话，问题"如果用 docker 容器挂载工作目录跑 AI，算不算安全沙箱"

**首次实战调用**：— （待发生：下次真的启动一个 AI agent 容器跑命令时回填）

---

## 下一条预占位（写新启发式时把这段替换）

<!--
## H-XXX [主题名]

**触发场景**：

**第一反应**：

**完整判断顺序**：

**例外 / 反例**：

**给自己的操作纪律**：

**来源**：[来源类型] — 简短描述（哪次场景/哪篇论文/谁告诉的）

**首次实战调用**：— （非 real-incident 类来源必填占位）
-->

---

## 月度复盘记录

> 每月最后一周做一次，对照"来源类型"的硬规则。

| 月份 | 总条数 | conversation 占比 | real-incident 占比 | 备注/下月动作 |
|------|-------|-----------------|------------------|--------------|
| 2026-05 | 3 | 100% | 0% | 起步阶段，conversation 占比高正常；6 月动作：**用 H-003 的 docker run 模板跑一次真实 AI agent**，让 H-003 升级为 `[real-incident]`，连带验证 H-001/H-002 |
