#!/bin/bash
# 启动 xinghan-ziwei-32b-v1 模型服务
# 镜像: reg.xxwolo.com/ai/lmsysorg-sglang:latest (sglang 0.4.1.post4)
# GPU: 1,3,4,5 (4x L20 46GB)，tensor-parallel-size=4
# 端口: 5290

set -e

CONTAINER_NAME="ziwei-32b-server"
IMAGE="reg.xxwolo.com/ai/lmsysorg-sglang:latest"
MODEL_PATH="/mnt/ai-llm/xinghan-ziwei-32b-v1"
PORT=5290
BASE_GPU_ID=3
TP_SIZE=4

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

echo "[INFO] 启动 xinghan-ziwei-32b-v1 服务..."
echo "[INFO] BASE_GPU_ID: ${BASE_GPU_ID} | 使用GPU: ${BASE_GPU_ID}~$((BASE_GPU_ID+TP_SIZE-1)) | TP: ${TP_SIZE} | PORT: ${PORT}"

docker run -d \
    --name "${CONTAINER_NAME}" \
    --gpus all \
    --ipc=host \
    --network=host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -v /mnt/ai-llm:/mnt/ai-llm:ro \
    "${IMAGE}" \
    python3 -m sglang.launch_server \
        --host 0.0.0.0 \
        --port "${PORT}" \
        --model-path "${MODEL_PATH}" \
        --served-model-name xinghan-ziwei-32b-v1 \
        --tensor-parallel-size "${TP_SIZE}" \
        --base-gpu-id "${BASE_GPU_ID}" \
        --log-requests \
        --show-time-cost

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
