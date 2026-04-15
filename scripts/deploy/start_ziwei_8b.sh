#!/bin/bash
# 启动 ziwei_intention_twostep_8b_v1 模型服务
# 镜像: reg-ai.cece.com/ai/sglang:v814 (sglang 0.4.6.post2)
# GPU: 6 (1x L20 46GB)，tensor-parallel-size=1
# 端口: 5291

set -e

CONTAINER_NAME="ziwei-8b-server"
IMAGE="reg-ai.cece.com/ai/sglang:v814"
MODEL_PATH="/mnt/ai-llm/ziwei_intention_twostep_8b_v1"
PORT=5291
BASE_GPU_ID=7
TP_SIZE=1

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

echo "[INFO] 启动 ziwei_intention_twostep_8b_v1 服务..."
echo "[INFO] BASE_GPU_ID: ${BASE_GPU_ID} | 使用GPU: ${BASE_GPU_ID} | TP: ${TP_SIZE} | PORT: ${PORT}"

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
        --served-model-name ziwei_intention_twostep_8b_v1 \
        --tensor-parallel-size "${TP_SIZE}" \
        --base-gpu-id "${BASE_GPU_ID}" \
        --log-requests \
        --show-time-cost

echo "[INFO] 容器已启动，等待服务就绪..."
echo "[INFO] 查看日志: docker logs -f ${CONTAINER_NAME}"
echo "[INFO] 健康检查: curl http://localhost:${PORT}/health"
echo ""
echo "[INFO] 等待服务启动（最多60秒）..."
for i in $(seq 1 12); do
    sleep 5
    if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
        echo "[OK] 服务已就绪！端口: ${PORT}"
        exit 0
    fi
    echo "[INFO] 等待中... ${i}/12 ($(( i * 5 ))s)"
done

echo "[WARN] 超时，请手动检查: docker logs ${CONTAINER_NAME}"
