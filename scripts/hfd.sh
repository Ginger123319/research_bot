#!/usr/bin/env bash
# hfd.sh - HuggingFace 模型/数据集下载脚本
# 支持镜像站、断点续传、aria2c/wget、文件过滤
#
# 用法：
#   hfd.sh <REPO_ID> [选项]
#
# 示例：
#   HF_ENDPOINT=https://hf-mirror.com hfd.sh deepseek-ai/DeepSeek-V2-Lite-Chat
#   hfd.sh wuchen01/DeepSeek-V2-Lite-Chat-All-LoRA --local-dir /mnt/models/lora
#   hfd.sh bigcode/the-stack --type dataset --include "*.py"
#   hfd.sh meta-llama/Llama-3-8B --token hf_xxx --exclude "*.bin"

set -euo pipefail

# ─── 默认值 ───────────────────────────────────────────────────────────────────
HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
HF_TOKEN="${HF_TOKEN:-}"
REPO_TYPE="model"       # model | dataset
REVISION="main"
LOCAL_DIR=""
INCLUDE_PATTERN=""
EXCLUDE_PATTERN=""
DOWNLOADER=""           # 自动检测 aria2c > wget
ARIA2_JOBS=5            # 并发文件数
ARIA2_CONNECTIONS=4     # 单文件并发连接数

# ─── 帮助 ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
用法: hfd.sh <REPO_ID> [选项]

选项:
  --type model|dataset   仓库类型 (默认: model)
  --revision BRANCH      分支/tag/commit (默认: main)
  --local-dir DIR        本地保存路径 (默认: 当前目录/REPO_NAME)
  --include PATTERN      只下载匹配的文件 (shell glob, 如 "*.safetensors")
  --exclude PATTERN      排除匹配的文件
  --token TOKEN          HuggingFace token (也可用 HF_TOKEN 环境变量)
  --tool aria2c|wget     强制指定下载工具
  -h, --help             显示帮助

环境变量:
  HF_ENDPOINT   镜像站地址 (默认: https://huggingface.co)
                国内可用: https://hf-mirror.com
  HF_TOKEN      访问私有模型的 token

示例:
  # 用镜像站下载
  HF_ENDPOINT=https://hf-mirror.com hfd.sh deepseek-ai/DeepSeek-V2-Lite-Chat

  # 只下载 safetensors 格式权重
  hfd.sh meta-llama/Llama-3-8B --include "*.safetensors" --include "*.json"

  # 下载到指定目录
  hfd.sh wuchen01/DeepSeek-V2-Lite-Chat-All-LoRA --local-dir /mnt/models/lora
EOF
    exit 0
}

# ─── 参数解析 ─────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage
REPO_ID="$1"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)       REPO_TYPE="$2"; shift 2 ;;
        --revision)   REVISION="$2"; shift 2 ;;
        --local-dir)  LOCAL_DIR="$2"; shift 2 ;;
        --include)    INCLUDE_PATTERN="${INCLUDE_PATTERN:+$INCLUDE_PATTERN|}$2"; shift 2 ;;
        --exclude)    EXCLUDE_PATTERN="${EXCLUDE_PATTERN:+$EXCLUDE_PATTERN|}$2"; shift 2 ;;
        --token)      HF_TOKEN="$2"; shift 2 ;;
        --tool)       DOWNLOADER="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

# ─── 初始化 ───────────────────────────────────────────────────────────────────
REPO_NAME="${REPO_ID##*/}"
LOCAL_DIR="${LOCAL_DIR:-$(pwd)/$REPO_NAME}"
CACHE_DIR="$LOCAL_DIR/.hfd"
METADATA_FILE="$CACHE_DIR/repo_metadata.json"
URLS_FILE="$CACHE_DIR/aria2c_urls.txt"
LAST_CMD_FILE="$CACHE_DIR/last_download_command"

mkdir -p "$LOCAL_DIR" "$CACHE_DIR"

# ─── 工具检测 ─────────────────────────────────────────────────────────────────
if [[ -z "$DOWNLOADER" ]]; then
    if command -v aria2c &>/dev/null; then
        DOWNLOADER="aria2c"
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"
    else
        echo "错误: 未找到 aria2c 或 wget，请先安装其中一个"
        exit 1
    fi
fi
echo "下载工具: $DOWNLOADER"

# ─── 构建请求头 ───────────────────────────────────────────────────────────────
AUTH_HEADER=""
[[ -n "$HF_TOKEN" ]] && AUTH_HEADER="Authorization: Bearer $HF_TOKEN"

curl_auth() {
    if [[ -n "$AUTH_HEADER" ]]; then
        curl -fsSL -H "$AUTH_HEADER" "$@"
    else
        curl -fsSL "$@"
    fi
}

# ─── 获取文件列表 ─────────────────────────────────────────────────────────────
API_TYPE="models"
[[ "$REPO_TYPE" == "dataset" ]] && API_TYPE="datasets"
API_URL="${HF_ENDPOINT}/api/${API_TYPE}/${REPO_ID}"
[[ "$REVISION" != "main" ]] && API_URL="${API_URL}?revision=${REVISION}"

# 检查是否需要重新拉取元数据
CURRENT_CMD="${REPO_ID}|${REPO_TYPE}|${REVISION}|${INCLUDE_PATTERN}|${EXCLUDE_PATTERN}"
LAST_CMD=""
[[ -f "$LAST_CMD_FILE" ]] && LAST_CMD=$(cat "$LAST_CMD_FILE")

if [[ "$CURRENT_CMD" != "$LAST_CMD" ]] || [[ ! -f "$METADATA_FILE" ]]; then
    echo "获取文件列表: $API_URL"
    if ! curl_auth "$API_URL" -o "$METADATA_FILE"; then
        echo "错误: 无法访问 $API_URL"
        echo "提示: 无法访问 HuggingFace 时，请设置镜像站:"
        echo "  export HF_ENDPOINT=https://hf-mirror.com"
        exit 1
    fi
    echo "$CURRENT_CMD" > "$LAST_CMD_FILE"
else
    echo "使用缓存的文件列表: $METADATA_FILE"
fi

# ─── 解析文件列表 ─────────────────────────────────────────────────────────────
if command -v jq &>/dev/null; then
    FILES=$(jq -r '.siblings[].rfilename' "$METADATA_FILE" 2>/dev/null)
else
    FILES=$(grep -o '"rfilename":"[^"]*"' "$METADATA_FILE" | awk -F'"' '{print $4}')
fi

if [[ -z "$FILES" ]]; then
    echo "错误: 无法解析文件列表，请检查 REPO_ID 是否正确"
    echo "API 响应: $(cat "$METADATA_FILE" | head -c 500)"
    exit 1
fi

TOTAL=$(echo "$FILES" | wc -l)
echo "仓库文件总数: $TOTAL"

# ─── 过滤文件 ─────────────────────────────────────────────────────────────────
filter_files() {
    local files="$1"

    # include 过滤（glob 转 regex，* → .*）
    if [[ -n "$INCLUDE_PATTERN" ]]; then
        local regex
        regex=$(echo "$INCLUDE_PATTERN" | sed 's/\./\\./g; s/\*/.*/g')
        files=$(echo "$files" | grep -E "$regex" || true)
    fi

    # exclude 过滤
    if [[ -n "$EXCLUDE_PATTERN" ]]; then
        local regex
        regex=$(echo "$EXCLUDE_PATTERN" | sed 's/\./\\./g; s/\*/.*/g')
        files=$(echo "$files" | grep -vE "$regex" || true)
    fi

    echo "$files"
}

FILTERED_FILES=$(filter_files "$FILES")
FILTERED_COUNT=$(echo "$FILTERED_FILES" | grep -c . || true)

if [[ "$FILTERED_COUNT" -eq 0 ]]; then
    echo "错误: 过滤后无匹配文件，请检查 --include/--exclude 参数"
    exit 1
fi

echo "过滤后待下载: $FILTERED_COUNT 个文件"

# ─── 生成下载任务 ─────────────────────────────────────────────────────────────
> "$URLS_FILE"

while IFS= read -r rfilename; do
    [[ -z "$rfilename" ]] && continue
    url="${HF_ENDPOINT}/${REPO_ID}/resolve/${REVISION}/${rfilename}"
    subdir="$LOCAL_DIR/$(dirname "$rfilename")"
    filename="$(basename "$rfilename")"

    if [[ "$DOWNLOADER" == "aria2c" ]]; then
        {
            echo "$url"
            echo " dir=$subdir"
            echo " out=$filename"
            echo " continue=true"
            [[ -n "$AUTH_HEADER" ]] && echo " header=$AUTH_HEADER"
        } >> "$URLS_FILE"
    else
        echo "$url" >> "$URLS_FILE"
    fi
done <<< "$FILTERED_FILES"

# ─── 执行下载 ─────────────────────────────────────────────────────────────────
echo ""
echo "开始下载 → $LOCAL_DIR"
echo "镜像站: $HF_ENDPOINT"
echo "────────────────────────────"

if [[ "$DOWNLOADER" == "aria2c" ]]; then
    aria2c \
        -x "$ARIA2_CONNECTIONS" \
        -j "$ARIA2_JOBS" \
        -s "$ARIA2_CONNECTIONS" \
        -k 1M \
        -c \
        --input-file="$URLS_FILE" \
        --save-session="$URLS_FILE" \
        --save-session-interval=30 \
        --console-log-level=warn \
        --summary-interval=10
else
    # wget 模式：逐文件下载以保留目录结构
    while IFS= read -r rfilename; do
        [[ -z "$rfilename" ]] && continue
        url="${HF_ENDPOINT}/${REPO_ID}/resolve/${REVISION}/${rfilename}"
        target_dir="$LOCAL_DIR/$(dirname "$rfilename")"
        mkdir -p "$target_dir"
        wget_args=(-c -q --show-progress -P "$target_dir")
        [[ -n "$AUTH_HEADER" ]] && wget_args+=(--header="$AUTH_HEADER")
        wget "${wget_args[@]}" "$url"
    done <<< "$FILTERED_FILES"
fi

echo ""
echo "下载完成: $LOCAL_DIR"
