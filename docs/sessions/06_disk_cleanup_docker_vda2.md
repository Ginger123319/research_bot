# 会话记录：/dev/vda2 磁盘空间清理

**日期**：2026-05-07  
**问题**：`/dev/vda2`（197G）使用率达 80%（151G），可用空间仅 39G  
**结果**：清理后使用 106G，使用率降至 56%，释放约 **45G**

---

## 一、排查过程

### 第一步：定位大目录

```bash
sudo du -hx --max-depth=1 / 2>/dev/null | sort -hr
```

发现 `/mnt` 是 Lustre 网络存储（不占本地磁盘），本地大目录为：

| 目录 | 大小 |
|------|------|
| `/var` | 92G |
| `/usr` | 25G |
| `/home` | 19.5G |
| `/data` | 11G |
| `/opt` | 2.1G |

### 第二步：下钻 /var

```bash
sudo du -hx --max-depth=1 /var | sort -hr
# /var/lib  87G
sudo du -hx --max-depth=1 /var/lib | sort -hr
# /var/lib/docker  86G
```

**根因：Docker 占用 86G**

```bash
sudo docker system df
# Images: 19个，72.2GB，可回收 31.47GB
# Containers: 5个，2.07GB
```

### 第三步：发现容器日志异常

```bash
sudo du -hx --max-depth=1 /var/lib/docker/containers | sort -hr
# 918d39e4...  16G  ← 单个容器日志文件
```

容器 `/friendly_jemison`（`cece_asr:v1.1`，运行了 2 周）的 stdout 日志达 **16G**，原因是服务持续将推理过程打印到 stdout，Docker 无限追加写入 json.log。

### 第四步：发现 /data

```bash
du -hx --max-depth=2 /data
# /data/venv/SpecForge-venv  11G
```

项目 SpecForge 的 Python venv，主要由 AI 推理依赖包构成：
`nvidia`（4.3G）、`torch`（1.7G）、`sgl_kernel`（1.5G）、`triton`（592M）等。

### 第五步：发现孤立层

`docker system df` 显示镜像 40.7G + 容器 2G ≈ 42.7G，但 `overlay2` 实际占 71G，**差 28G**。  
原因：之前删除 `cece_asr` 镜像时产生了大量孤立 overlay2 层（276层 → 实际只需 61 层）。

---

## 二、清理操作

### 1. 停止并删除容器

```bash
sudo docker stop friendly_jemison && sudo docker rm friendly_jemison
sudo docker rm cece_asr_local_test
```

释放：容器读写层 + **16G 日志文件**

### 2. 删除 cece_asr 全系列镜像（13个 tag + faster-whisper）

```bash
sudo docker images | grep "cece_asr\|faster-whisper" | awk '{print $1":"$2}' | xargs sudo docker rmi
```

### 3. 清理孤立层和悬空镜像

```bash
sudo docker system prune -f
```

释放：**~28G** 孤立 overlay2 层

### 4. 配置 Docker 日志轮转（防止复发）

```bash
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "3" }
}
EOF
sudo systemctl reload docker
```

> 注意：此配置只对新启动的容器生效，已运行容器需重启才能应用。

---

## 三、清理结果

| 指标 | 清理前 | 清理后 |
|------|--------|--------|
| 磁盘使用 | 151G | **106G** |
| 可用空间 | 39G | **84G** |
| 使用率 | 80% | **56%** |
| Docker 占用 | 86G | 41G |
| overlay2 层数 | 276 | 61 |

---

## 四、关键知识点

### Docker 日志机制

- 容器内进程输出到 **stdout/stderr** 的内容（包括 `print()`）由 Docker 引擎统一收集，写入宿主机的 `/var/lib/docker/containers/<id>/<id>-json.log`
- `daemon.json` 的 `max-size`/`max-file` 限制的是这个 json.log 文件，与容器内服务自己写的日志文件无关
- 服务自己写的文件日志需在服务层或通过宿主机 logrotate 管理

### overlay2 孤立层

- 删除镜像后，如果没有执行 `docker system prune`，部分层文件可能变为孤立状态，仍占磁盘但不被任何镜像/容器引用
- `docker system df` 的统计值与 `du overlay2` 不符时，通常说明存在孤立层，执行 `docker system prune -f` 清理

### ext4 保留块

- ext4 默认保留 5% 空间给 root（约 `197G × 5% ≈ 8G`），计入 `df` 已用但 `du` 看不到
- 可通过 `sudo tune2fs -m 1 /dev/vda2` 调低至 1%，释放约 6G

---

## 五、后续建议

1. **定期清理**：每月执行 `docker system prune -f`，清理孤立层和已退出容器
2. **镜像版本管理**：同一镜像保留 2-3 个版本即可，避免像 cece_asr 那样堆积 13 个 tag
3. **SpecForge venv**：`/data/venv/SpecForge-venv`（11G）若项目废弃可删除，再释放 11G
4. **CUDA 本地仓库**：`/var/cuda-repo-ubuntu2204-12-4-local`（3.3G）驱动装好后可删除
