#!/bin/bash
# 启动 tianji-querysafety-4b-v2-3 模型服务
# 镜像: reg-ai.cece.com/ai/sglang:v814
# GPU: 3,4,5,6 (4x L20 46GB)，tensor-parallel-size=4
# 端口: 8361

set -e

CONTAINER_NAME="tianji-querysafety-4b-server"
IMAGE="reg-ai.cece.com/ai/sglang:v814"
MODEL_PATH="/mnt/ai-llm/tianji_query_safety/v2p3_ep1"
CHAT_TEMPLATE="${MODEL_PATH}/chat_template.jinja"
PORT=8361
GPU_DEVICES="3,4,5,6"   # 当前空闲的4张 L20，调整为实际可用 GPU ID
TP_SIZE=4
DP_SIZE=1

# 检查是否已有同名容器在运行
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[WARN] 容器 ${CONTAINER_NAME} 已在运行，跳过启动"
    echo "[INFO] 查看日志: docker logs -f ${CONTAINER_NAME}"
    exit 0
fi

# 清理已停止的同名容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[INFO] 清理已停止的旧容器..."
    docker rm "${CONTAINER_NAME}"
fi

echo "[INFO] 启动 tianji-querysafety-4b-v2-3 服务..."
echo "[INFO] GPU: ${GPU_DEVICES} | TP: ${TP_SIZE} | DP: ${DP_SIZE} | PORT: ${PORT}"

docker run -d \
    --name "${CONTAINER_NAME}" \
    --gpus "\"device=${GPU_DEVICES}\"" \
    --ipc=host \
    --network=host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -v /mnt/ai-llm:/mnt/ai-llm:ro \
    "${IMAGE}" \
    python3 -m sglang.launch_server \
        --served-model-name tianji-querysafety-4b-v2-3 \
        --model-path "${MODEL_PATH}" \
        --chat-template "${CHAT_TEMPLATE}" \
        --host 0.0.0.0 \
        --port "${PORT}" \
        --tp-size "${TP_SIZE}" \
        --dp-size "${DP_SIZE}" \
        --log-requests \
        --show-time-cost \
        --enable-metrics \
        --mem-fraction-static 0.85 \
        --context-length 8192

echo "[INFO] 容器已启动，等待服务就绪..."
echo "[INFO] 查看日志: docker logs -f ${CONTAINER_NAME}"
echo "[INFO] 健康检查: curl http://localhost:${PORT}/health"
echo ""
echo "[INFO] 等待服务启动（最多120秒）..."
for i in $(seq 1 24); do
    sleep 5
    if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
        echo "[OK] 服务已就绪！端口: ${PORT}"
        exit 0
    fi
    echo "[INFO] 等待中... ${i}/24 ($(( i * 5 ))s)"
done

echo "[WARN] 超时，请手动检查: docker logs ${CONTAINER_NAME}"
exit 1
