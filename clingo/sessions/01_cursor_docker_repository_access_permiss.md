# Docker repository access permissions
_Exported on 2026/3/9 at GMT+8 19:14:36 from Cursor (2.5.26)_

---

**User**

我刚刚想做关于制定镜像的拉取

(SpecForge) ceceadmin@VM-208-11-ubuntu:/mnt/ai-infra/users/wnd/workspace/repo/SpecForge$ docker pull reg.xxwolo.com/ai/lmsysorg-sglang:latest
Error response from daemon: unauthorized: unauthorized to access repository: ai/lmsysorg-sglang, action: pull: unauthorized to access repository: ai/lmsysorg-sglang, action: pull


是不是docker demon.json 可以查看当前使用这个仓库的账户是否有权限？要如何设置查询

---

**Cursor**

这个问题是 Docker 私有仓库认证问题，和 `daemon.json` 关系不大。`daemon.json` 主要配置镜像加速、存储驱动等，**认证信息存放在 `~/.docker/config.json`**。

## 排查步骤

### 1. 查看当前登录的认证信息

找到问题了。

## 诊断结果

当前 `~/.docker/config.json` 中记录的登录账户是：

- **用户名**: `zhangkai`
- **仓库**: `reg.xxwolo.com`

错误原因：用户 `zhangkai` **没有权限**访问 `ai/lmsysorg-sglang` 这个镜像仓库。

## 解决方案

### 方案一：换用有权限的账号重新登录

```bash
docker logout reg.xxwolo.com
docker login reg.xxwolo.com -u <有权限的用户名>
```

### 方案二：联系仓库管理员

让管理员为 `zhangkai` 账号授予 `ai/lmsysorg-sglang` 仓库的 **pull 权限**（Harbor/Registry 后台分配）。

### 验证权限是否生效

```bash
# 重新登录后测试
docker pull reg.xxwolo.com/ai/lmsysorg-sglang:latest
```

## 补充说明

| 文件 | 作用 |
|------|------|
| `~/.docker/config.json` | 存储各仓库的登录认证 token（当前用户） |
| `/etc/docker/daemon.json` | Docker 守护进程全局配置（镜像加速、insecure-registries 等） |
| `/root/.docker/config.json` | root 用户的认证（用 sudo docker 时读取这里） |

> 注意：如果你用 `sudo docker pull`，读取的是 `/root/.docker/config.json`，可能和当前用户的认证不同。可以用 `sudo cat /root/.docker/config.json` 检查。

---

**User**

OK 我设置用户赋予权限后 下载成功了
我现在想对于
ceceadmin@VM-208-11-ubuntu:/mnt/ai-infra/users/wnd/workspace/repo/SpecForge$ docker images -a
REPOSITORY                                 TAG                        IMAGE ID       CREATED         SIZE
reg-ai.cece.com/ai/sglang                  v814                       fd9d21b1e84e   10 months ago   14.7GB
reg.xxwolo.com/ai/lmsysorg-sglang          latest                     36c3a6baa439   14 months ago   19.6GB
 
2个容器进行开启并 查看它们的sglang 版本 要如何操作？

---

**Cursor**

## 查看两个镜像中的 sglang 版本

不需要完整启动容器，直接用 `docker run --rm` 临时运行命令即可：

### 方法一：直接查询版本（推荐，快速）

```bash
# 查看第一个镜像的 sglang 版本
docker run --rm reg-ai.cece.com/ai/sglang:v814 python -c "import sglang; print(sglang.__version__)"

# 查看第二个镜像的 sglang 版本
docker run --rm reg.xxwolo.com/ai/lmsysorg-sglang:latest python -c "import sglang; print(sglang.__version__)"
```

### 方法二：用 pip show 查询

```bash
docker run --rm reg-ai.cece.com/ai/sglang:v814 pip show sglang

docker run --rm reg.xxwolo.com/ai/lmsysorg-sglang:latest pip show sglang
```

### 方法三：进入容器交互式查看（适合顺带检查其他内容）

```bash
# 进入第一个容器
docker run --rm -it reg-ai.cece.com/ai/sglang:v814 bash

# 进入后执行
python -c "import sglang; print(sglang.__version__)"
pip show sglang
# 退出
exit
```

---

你现在可以先跑方法一，我来帮你执行吗？还是你在本地终端自己跑？如果报错（比如 GPU 相关启动失败）可以加 `--entrypoint bash` 参数绕过默认入口：

```bash
docker run --rm --entrypoint bash reg-ai.cece.com/ai/sglang:v814 -c "pip show sglang"
```

---

**User**

我用的方法二 

ceceadmin@VM-208-11-ubuntu:/mnt/ai-infra/users/wnd/workspace/repo/SpecForge$ docker run --rm reg.xxwolo.com/ai/lmsysorg-sglang:latest pip show sglang

==========
== CUDA ==
==========

CUDA Version 12.4.1

Container image Copyright (c) 2016-2023, NVIDIA CORPORATION & AFFILIATES. All rights reserved.

This container image and its contents are governed by the NVIDIA Deep Learning Container License.
By pulling and using the container, you accept the terms and conditions of this license:
https://developer.nvidia.com/ngc/nvidia-deep-learning-container-license

A copy of this license is made available in this container at /NGC-DL-CONTAINER-LICENSE for your convenience.

WARNING: The NVIDIA Driver was not detected.  GPU functionality will not be available.
   Use the NVIDIA Container Toolkit to start this container with GPU support; see
   https://docs.nvidia.com/datacenter/cloud-native/ .

Name: sglang
Version: 0.4.1.post4
Summary: SGLang is yet another fast serving framework for large language models and vision language models.
Home-page: https://github.com/sgl-project/sglang
Author:
Author-email:
License:
Location: /usr/local/lib/python3.10/dist-packages
Editable project location: /sgl-workspace/sglang/python
Requires: IPython, numpy, requests, setproctitle, tqdm
Required-by:
ceceadmin@VM-208-11-ubuntu:/mnt/ai-infra/users/wnd/workspace/repo/SpecForge$ docker run --rm reg-ai.cece.com/ai/sglang:v814 pip show sglang

==================================
== Triton Inference Server Base ==
==================================

NVIDIA Release 24.04 (build 90085237)

Copyright (c) 2018-2023, NVIDIA CORPORATION & AFFILIATES.  All rights reserved.

Various files include modifications (c) NVIDIA CORPORATION & AFFILIATES.  All rights reserved.

This container image and its contents are governed by the NVIDIA Deep Learning Container License.
By pulling and using the container, you accept the terms and conditions of this license:
https://developer.nvidia.com/ngc/nvidia-deep-learning-container-license

WARNING: The NVIDIA Driver was not detected.  GPU functionality will not be available.
   Use the NVIDIA Container Toolkit to start this container with GPU support; see
   https://docs.nvidia.com/datacenter/cloud-native/ .

Name: sglang
Version: 0.4.6.post2
Summary: SGLang is yet another fast serving framework for large language models and vision language models.
Home-page: https://github.com/sgl-project/sglang
Author:
Author-email:
License:
Location: /usr/local/lib/python3.10/dist-packages
Editable project location: /sgl-workspace/sglang/python
Requires: aiohttp, IPython, numpy, requests, setproctitle, tqdm
Required-by:
ceceadmin@VM-208-11-ubuntu:/mnt/ai-infra/users/wnd/workspace/repo/SpecForge$

然后需要在 reg.xxwolo.com/ai/lmsysorg-sglang:latest 镜像内部署 
python3 -m sglang.launch_server --host 0.0.0.0 --tensor-parallel-size 8 --model-path /mnt/ai-llm/xinghan-ziwei-32b-v1  --port 5290 --served-model-name xinghan-ziwei-32b-v1  --log-requests --show-time-cost

在 reg-ai.cece.com/ai/sglang:v814 内部署
python3 -m sglang.launch_server --host 0.0.0.0 --tensor-parallel-size 1 --model-path /mnt/ai-llm/ziwei_intention_twostep_8b_v1  --port 5291 --served-model-name ziwei_intention_twostep_8b_v1  --log-requests --show-time-cost

目前我都不知道这2个模型的是否可以正常部署？

(.venv) ceceadmin@VM-208-11-ubuntu:/mnt/ai-infra/users/wnd/workspace/execute/CosyVoice3$ nvidia-smi
Mon Mar  9 17:42:15 2026
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 570.158.01             Driver Version: 570.158.01     CUDA Version: 12.8     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA L20                     On  |   00000000:23:00.0 Off |                    0 |
| N/A   29C    P0             73W /  350W |    4931MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   1  NVIDIA L20                     On  |   00000000:33:00.0 Off |                    0 |
| N/A   27C    P8             33W /  350W |       3MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   2  NVIDIA L20                     On  |   00000000:34:00.0 Off |                    0 |
| N/A   30C    P0             77W /  350W |   15517MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   3  NVIDIA L20                     On  |   00000000:43:00.0 Off |                    0 |
| N/A   25C    P8             34W /  350W |       3MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   4  NVIDIA L20                     On  |   00000000:63:00.0 Off |                    0 |
| N/A   27C    P8             34W /  350W |       3MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   5  NVIDIA L20                     On  |   00000000:83:00.0 Off |                    0 |
| N/A   27C    P8             36W /  350W |       5MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   6  NVIDIA L20                     On  |   00000000:84:00.0 Off |                    0 |
| N/A   25C    P8             33W /  350W |       3MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   7  NVIDIA L20                     On  |   00000000:A3:00.0 Off |                    0 |
| N/A   29C    P8             48W /  350W |       5MiB /  46068MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI              PID   Type   Process name                        GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A         3947654      C   python                                 4922MiB |
|    2   N/A  N/A          937829      C   python                                15496MiB |
+-----------------------------------------------------------------------------------------+

但是我知道 我先开发机器L20 机器还是比较多的空余卡，部署一个  32B 权重应该使用4张卡就可以了， 8B的参数使用单卡部署，你可以写2个基于宿主机启动脚本来执行者2个模型的服务启动吗？

---

**Cursor**

根据当前 GPU 使用情况分析：
- GPU 0、2 已被占用，其余 6 张卡空闲
- 32B 模型用 GPU 1,3,4,5（4张 L20 × 46GB = 184GB，足够）
- 8B 模型用 GPU 6（单张 46GB，足够）

两个模型路径都存在，现在创建启动脚本：

两个脚本已创建完毕，位于 `scripts/` 目录下。

## 使用方式

```bash
# 启动 32B 模型（建议先启动，加载时间较长）
bash /mnt/ai-infra/users/wnd/workspace/repo/SpecForge/scripts/start_ziwei_32b.sh

# 启动 8B 模型
bash /mnt/ai-infra/users/wnd/workspace/repo/SpecForge/scripts/start_ziwei_8b.sh
```

## 脚本设计说明

| 项目 | 32B 模型 | 8B 模型 |
|------|---------|---------|
| 容器名 | `ziwei-32b-server` | `ziwei-8b-server` |
| 使用 GPU | 1,3,4,5（4张空闲卡） | 6（单张空闲卡） |
| tensor-parallel | 4 | 1 |
| 端口 | 5290 | 5291 |
| 启动等待 | 120s | 60s |

## 常用运维命令

```bash
# 查看实时日志
docker logs -f ziwei-32b-server
docker logs -f ziwei-8b-server

# 检查服务健康状态
curl http://localhost:5290/health
curl http://localhost:5291/health

# 停止服务
docker stop ziwei-32b-server && docker rm ziwei-32b-server
docker stop ziwei-8b-server && docker rm ziwei-8b-server
```

> **注意**：GPU 0 和 GPU 2 当前有 Python 进程在用（4.9GB + 15.5GB），脚本已刻意跳开这两张卡，避免显存冲突。如果在部署过程中其他进程释放了卡，也可以把 32B 的 GPU 改为 `0,1,3,4` 等任意4张空闲卡。

---

**User**

你为什么将脚本写到 /mnt/ai-infra/users/wnd/workspace/repo/SpecForge/scripts/ 目录下去了？
你先写到@tmp/scripts 目录下吧

---

**Cursor**

抱歉，我错误地把脚本写到了 SpecForge 项目目录下。现在移到正确位置。

已移动到正确位置，执行权限保留完好。现在两个脚本在：

```
tmp/scripts/
├── start_ziwei_32b.sh   ← 32B 模型 (GPU 1,3,4,5 | 端口 5290)
└── start_ziwei_8b.sh    ← 8B 模型  (GPU 6 | 端口 5291)
```

启动命令：

```bash
# 在 CosyVoice3 项目根目录下
bash tmp/scripts/start_ziwei_32b.sh
bash tmp/scripts/start_ziwei_8b.sh
```

---

**User**

@code block (2-3) 
docker logs -f 13a42812831f8ada6e1f6fee34c7616682c4d14ee673cac2068a229090f8ec29
File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 1331, in kill
    self._send_signal(signal.SIGKILL)
  File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 1256, in _send_signal
    self._raise_if_pid_reused()
  File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 461, in _raise_if_pid_reused
    if self._pid_reused or (not self.is_running() and self._pid_reused):
  File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 636, in is_running
    self._pid_reused = self != Process(self.pid)
  File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 319, in __init__
    self._init(pid)
  File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 355, in _init
    self._ident = self._get_ident()
  File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 396, in _get_ident
    return (self.pid, self.create_time())
  File "/usr/local/lib/python3.10/dist-packages/psutil/__init__.py", line 778, in create_time
    self._create_time = self._proc.create_time()
  File "/usr/local/lib/python3.10/dist-packages/psutil/_pslinux.py", line 1716, in wrapper
    return fun(self, *args, **kwargs)
  File "/usr/local/lib/python3.10/dist-packages/psutil/_pslinux.py", line 1957, in create_time
    ctime = float(self._parse_stat_file()['create_time'])
  File "/usr/local/lib/python3.10/dist-packages/psutil/_pslinux.py", line 1716, in wrapper
    return fun(self, *args, **kwargs)
  File "/usr/local/lib/python3.10/dist-packages/psutil/_common.py", line 508, in wrapper
    raise raise_from(err, None)
  File "<string>", line 3, in raise_from
  File "/usr/local/lib/python3.10/dist-packages/psutil/_common.py", line 506, in wrapper
    return fun(self)
  File "/usr/local/lib/python3.10/dist-packages/psutil/_pslinux.py", line 1784, in _parse_stat_file
    data = bcat("%s/%s/stat" % (self._procfs_path, self.pid))
  File "/usr/local/lib/python3.10/dist-packages/psutil/_common.py", line 851, in bcat
    return cat(fname, fallback=fallback, _open=open_binary)
  File "/usr/local/lib/python3.10/dist-packages/psutil/_common.py", line 839, in cat
    with _open(fname) as f:
RecursionError: maximum recursion depth exceeded while calling a Python object
你根据dock二信息排查一下？

---

**Cursor**

让我先看完整的容器日志来定位问题根因。

根因已找到，问题有两个：

**1. 真正的根因：`RuntimeError: No CUDA GPUs are available`**
容器根本没拿到 GPU，是因为脚本里 `--gpus` 参数的引号写法有误，Docker 没能正确解析，导致容器内看不到任何 GPU。

**2. 连锁反应：RecursionError**
GPU 初始化失败 → sglang 触发 SIGQUIT 信号 → `sigquit_handler` 递归调用自身 → psutil 栈溢出。这是错误处理的 bug，不是真正原因。

现在修复两个脚本的 `--gpus` 写法，同时修正容器内 `CUDA_VISIBLE_DEVICES`（宿主机 GPU 1,3,4,5 映射到容器内后编号变成 0,1,2,3）：

问题很清楚，修复两个脚本：

先清理旧容器，然后重新启动 32B：

还有一个问题，`--gpus "device=4,5,6,7"` 的格式在部分 Docker 版本下会报这个错。改用 `NVIDIA_VISIBLE_DEVICES` 环境变量方式，这是最兼容的写法：

容器已成功启动，正在等待模型加载。查看实时日志确认 GPU 是否正常：

GPU 已被识别了（第一个问题解决），但出现新错误：**GPU 内存不均衡**。现在运行 `nvidia-smi` 查看当前实际状态：

找到原因了。GPUs 5 和 7 用了 5MiB，而 4 和 6 用了 3MiB，sglang 的内存均衡检查非常严格，2MiB 的差异也会触发。

换用内存完全相同的 GPU：**32B 用 1,3,4,6（均为 3MiB），8B 用 5（单卡）**：

仍然不均衡。先检查现在 GPU 实际状态和 Docker 版本，找到正确的 `--gpus` 用法：

换用更兼容的 `--runtime=nvidia` 方式，这是最稳定的 GPU 挂载方式：

先测试一下 `--gpus all` + `NVIDIA_VISIBLE_DEVICES` 在容器内实际看到哪些 GPU：

根本原因找到了！容器内 `NVIDIA_VISIBLE_DEVICES` 没有生效，**仍然看到全部 8 张 GPU**，sglang 默认从 GPU 0 开始用 GPU 0,1,2,3，而 GPU 0 和 GPU 2 都被占用了，导致显存严重不均衡。

**解决方案**：使用 sglang 的 `--base-gpu-id` 参数，直接跳过被占用的 GPU，指定从哪张卡开始：

- 32B 模型：`--base-gpu-id 3` → 使用 GPU 3,4,5,6（均空闲）
- 8B 模型：`--base-gpu-id 7` → 使用 GPU 7（空闲）

现在重新启动 32B 验证：

**模型已经开始正常加载了！** `base_gpu_id=3` 生效，4 个 TP worker 都显示 `Load weight begin`，正在加载 safetensors 权重文件（共 14 个 shard）。

继续等待加载完成：

正在加载中（21% / 14 shards），模型较大，继续等待：

加载进度 57%，速度约每 shard 30秒，预计还需 ~3 分钟完成全部 14 个 shard。到目前为止一切正常，没有任何报错。

## 进度总结

| 问题 | 原因 | 解决方式 |
|------|------|---------|
| `No CUDA GPUs are available` | `--gpus "\"device=..."` 引号嵌套错误，Docker 无法解析 | 改为 `--gpus all` |
| `cannot set both Count and DeviceIDs` | `--gpus "device=..."` 在 Docker 28.4 下仍有问题 | 移除 device 指定 |
| `NVIDIA_VISIBLE_DEVICES` 无效 | 容器内 env 不能覆盖 Docker runtime 的 GPU 分配，容器仍看到全部 8 张卡 | 放弃该方案 |
| `memory capacity is unbalanced` | `base_gpu_id=0` 默认从 GPU 0 开始，包含了 GPU 0(4.9G占用) 和 GPU 2(15.5G占用) | 添加 `--base-gpu-id 3`，使用 GPU 3,4,5,6 |

模型正在加载中，完成后可用 `curl http://localhost:5290/health` 验证。

