#!/bin/bash
# Phase 1 自动饱和探测循环 — xinghan-guoxue-72b-v1-2-reason V2
#
# 真实线上数据集，远端 endpoint，SLA: TTFS P90 ≤ 1.5s, E2E P90 ≤ 180s
# 从 con=5 起跳，翻倍 → +10 两段式步进，直至吞吐增幅 < 1% 停止。
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_guoxue8tp_v2.sh
#   INIT_CON=20 bash scripts/benchmark/run_phase1_auto_guoxue8tp_v2.sh  # 续跑

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions"
TARGET_MODEL="xinghan-guoxue-72b-v1-2-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv"
MAX_COMPLETION_TOKENS=4096
TIME_LIMIT_SECS=300        # 每档 5min
TARGET_MUL=1500            # NUM_REQUESTS = CON × TARGET_MUL（动态上限保护）

# ── 初始并发 ─────────────────────────────────────────────────
INIT_CON="${INIT_CON:-5}"

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/guoxue-v2-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

DATASET_DATA_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))

echo "========================================================"
echo "Phase 1 自动饱和探测 — guoxue-72b V2（真实线上数据）"
echo "  初始并发: ${INIT_CON}"
echo "  每档时长: ${TIME_LIMIT_SECS}s"
echo "  数据集: $(basename ${DATASET_PATH}) (${DATASET_DATA_ROWS} 条)"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
PREV_DIR=""
PREV_THROUGHPUT=0
MAX_ITERS=15

for iter in $(seq 1 ${MAX_ITERS}); do
    LEVEL_DIR="${OUTPUT_BASE}/con${CURRENT_CON}"

    # 动态计算 NUM_REQUESTS：目标 CON×1500，但不超数据集上限
    MAX_MUL=$(${PYTHON} -c "print(int(${DATASET_DATA_ROWS} / max(${CURRENT_CON}, 1)))")
    NUM_REQUESTS_MUL=$(( TARGET_MUL < MAX_MUL ? TARGET_MUL : MAX_MUL ))
    NUM_REQUESTS=$(( CURRENT_CON * NUM_REQUESTS_MUL ))

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 档  并发=${CURRENT_CON}  num_requests=${NUM_REQUESTS}"
    echo "────────────────────────────────────────────────────────"

    if [[ -d "${LEVEL_DIR}" ]] && ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ⏭ 已有结果，跳过执行"
    else
        mkdir -p "${LEVEL_DIR}"
        cd "${LLM_BENCHMARK_ROOT}"
        "${PYTHON}" -m llm_benchmark.benchmark.benchmark \
            --exp-name       "guoxue_v2_phase1_con${CURRENT_CON}" \
            --dataset-path   "${DATASET_PATH}" \
            --url            "${SERVER_URL}" \
            --model          "${TARGET_MODEL}" \
            --max-concurrency "${CURRENT_CON}" \
            --num-requests   "${NUM_REQUESTS}" \
            --request-time-limit "${TIME_LIMIT_SECS}" \
            --output-dir     "${LEVEL_DIR}" \
            --no-kvcache \
            --shuffle \
            --tokenizer      "${TOKENIZER}" \
            --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
            || echo "⚠️ con=${CURRENT_CON} 异常，继续分析"
        cd "${PROJECT_DIR}"
    fi

    # ── 分析本档结果 ──────────────────────────────────────────
    METRICS=$(${PYTHON} "${ANALYZE}" \
        --phase 1 \
        --dir "${LEVEL_DIR}" \
        --ttfs-p90-limit 1.5 \
        --e2e-p90-limit 180.0 \
        2>/dev/null || echo "PARSE_ERROR")

    echo "${METRICS}"

    THROUGHPUT=$(echo "${METRICS}" | grep -oP 'decode_throughput\s*[=:]\s*\K[\d.]+' || echo "0")
    if [[ "${THROUGHPUT}" == "0" || "${THROUGHPUT}" == "" ]]; then
        echo "  ⚠️ 无法解析吞吐，跳过此档"
        CURRENT_CON=$(( CURRENT_CON + 10 ))
        continue
    fi

    # ── 饱和判断 ─────────────────────────────────────────────
    if [[ "${PREV_THROUGHPUT}" == "0" ]]; then
        echo "  第一档，继续翻倍"
        PREV_THROUGHPUT="${THROUGHPUT}"
        CURRENT_CON=$(( CURRENT_CON * 2 ))
        PREV_DIR="${LEVEL_DIR}"
        continue
    fi

    INCREASE=$(${PYTHON} -c "
prev=${PREV_THROUGHPUT}; curr=${THROUGHPUT}
if prev > 0:
    pct = (curr - prev) / prev * 100
    print(f'{pct:.2f}')
else:
    print('999')
")

    echo "  吞吐增幅: ${INCREASE}%  (${PREV_THROUGHPUT} → ${THROUGHPUT} tokens/s)"

    SATURATED=$(${PYTHON} -c "print('yes' if float('${INCREASE}') < 1.0 else 'no')")
    NEAR_SAT=$(${PYTHON} -c "print('yes' if float('${INCREASE}') < 10.0 else 'no')")

    if [[ "${SATURATED}" == "yes" ]]; then
        echo ""
        echo "✅ 饱和确认！增幅 < 1%，停止探测"
        echo ""
        MAX_RPS_EST=$(echo "${METRICS}" | grep -oP 'max_rps_estimate=\K[\d.]+' || echo "N/A")
        AVG_OUT=$(echo "${METRICS}" | grep -oP 'avg_output_len=\K[\d.]+' || echo "N/A")
        START_RPS=$(${PYTHON} -c "print(round(float('${MAX_RPS_EST}') * 1.2, 4))" 2>/dev/null || echo "N/A")

        cat > "${CHECKPOINT}" << EOF
# Phase 1 检查点 — guoxue-72b V2

| 指标 | 值 |
|------|-----|
| peak_decode_throughput | ${THROUGHPUT} tokens/s |
| avg_output_len | ${AVG_OUT} tokens |
| max_rps_estimate | ${MAX_RPS_EST} req/s |
| max_running_concurrency | ${CURRENT_CON} |
| **Phase 2 起始 QPS** | **${START_RPS} req/s**（max_rps × 1.2）|

## 饱和确认
最后两档吞吐增幅 ${INCREASE}% < 1%，已饱和。

## Phase 2 启动命令
\`\`\`bash
PEAK_RPS=${MAX_RPS_EST} START_RPS=${START_RPS} \\
  bash scripts/benchmark/run_phase2_auto_guoxue8tp_v2.sh
\`\`\`
EOF
        echo "  检查点已写入: ${CHECKPOINT}"
        echo ""
        echo "  ▶ 下一步："
        echo "    PEAK_RPS=${MAX_RPS_EST} START_RPS=${START_RPS} \\"
        echo "      bash scripts/benchmark/run_phase2_auto_guoxue8tp_v2.sh"
        break
    fi

    PREV_THROUGHPUT="${THROUGHPUT}"
    PREV_DIR="${LEVEL_DIR}"

    if [[ "${NEAR_SAT}" == "yes" ]]; then
        echo "  接近饱和（1%~10%），切换 +10 线性步进"
        CURRENT_CON=$(( CURRENT_CON + 10 ))
    else
        echo "  未饱和（>10%），继续翻倍"
        CURRENT_CON=$(( CURRENT_CON * 2 ))
    fi
done

echo ""
echo "========================================================"
echo "Phase 1 完成，输出目录: ${OUTPUT_BASE}"
echo "========================================================"
