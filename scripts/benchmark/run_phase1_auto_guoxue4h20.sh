#!/bin/bash
# Phase 1 自动饱和探测循环 — xinghan-guoxue-72b-v1-2-reason 4×H20
#
# 真实线上数据集 V2，远端 H20 endpoint，SLA: TTFS P90 ≤ 1.5s, E2E P90 ≤ 180s
# 先验：H20 5×L20（单卡），4H20 vs 8L20 总吞吐 ≈ 2.5× → 饱和点 ~75，从 con=60 起跳
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_guoxue4h20.sh
#   INIT_CON=80 bash scripts/benchmark/run_phase1_auto_guoxue4h20.sh  # 续跑

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-guoxue-p72b-v12-reason/v1/chat/completions"
TARGET_MODEL="infra-xinghan-guoxue-p72b-v12-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv"
MAX_COMPLETION_TOKENS=4096
TIME_LIMIT_SECS=300        # 每档 5min
# 长推理模型（E2E P90 ≈ 130s）：300s 内每槽只完成约 2~3 次
# NUM_REQUESTS 只要大于实际完成数即可，真正控制时长的是 --request-time-limit
# 公式：CON × ceil(TIME_LIMIT / est_e2e_sec) × 3 = CON × ceil(300/130) × 3 ≈ CON × 9
# 取 CON × 20 作为安全上限（约 1200，远超实际 ~138，但不会因数据集不够而提前停止）
REQ_PER_CON=20
AVG_OUTPUT_LEN=2204        # 同 eagle3_4h20；Phase 0 原始值 1386 有数据缺陷，使用 Phase 1 实测值

# ── 初始并发（先验：H20 5×L20 × 4GPU/8GPU = 2.5×，L20 饱和 con=30 → H20 ~75）──
INIT_CON="${INIT_CON:-60}"

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/guoxue-v2-h20-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

# 用 python csv reader 正确统计行数（CSV 含嵌入换行，wc -l 会严重虚高）
DATASET_DATA_ROWS=$(${PYTHON} -c "
import csv
count = 0
with open('${DATASET_PATH}', newline='', encoding='utf-8') as f:
    reader = csv.reader(f)
    next(reader)
    for _ in reader:
        count += 1
print(count)
" 2>/dev/null || echo "unknown")

echo "========================================================"
echo "Phase 1 自动饱和探测 — guoxue-72b V2（4×H20）"
echo "  初始并发: ${INIT_CON}（先验加速，跳过低档位爬坡）"
echo "  每档时长: ${TIME_LIMIT_SECS}s"
echo "  数据集: $(basename ${DATASET_PATH}) (${DATASET_DATA_ROWS} 条)"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
PREV_THROUGHPUT=0
PEAK_THROUGHPUT=0
PEAK_MAX_RPS=0
PEAK_AVG_OUT="N/A"
PEAK_CON=0
MAX_ITERS=15

for iter in $(seq 1 ${MAX_ITERS}); do
    LEVEL_DIR="${OUTPUT_BASE}/con${CURRENT_CON}"

    # 长推理模型（E2E ~130s）：300s 内每槽约完成 300/130 ≈ 2~3 次
    # num_requests 只要 > 实际完成数即可，--request-time-limit 才是真正控制时长的参数
    # CON × REQ_PER_CON(=20): con=60 → 1200，实际完成 ~138，充足且不浪费
    NUM_REQUESTS=$(( CURRENT_CON * REQ_PER_CON ))

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
            --exp-name       "guoxue_v2_h20_phase1_con${CURRENT_CON}" \
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
        --avg-output-len-phase0 "${AVG_OUTPUT_LEN}" \
        2>/dev/null || echo "PARSE_ERROR")

    echo "${METRICS}"

    THROUGHPUT=$(echo "${METRICS}" | grep -oP 'decode_throughput\s*[=:]\s*\K[\d.]+' || echo "0")
    # ⚠️ 修复：max_rps_estimate 的输出格式为 "A / B = C req/s"，需匹配最终值 C
    # 错误写法: grep -oP 'max_rps_estimate\s*[=:]\s*\K[\d.]+' → 会匹配到 A（tokens/s）
    # 正确写法: 匹配最后一个 = 后面的数值
    CUR_MAX_RPS=$(echo "${METRICS}" | grep -oP 'max_rps_estimate\s*=\s*[\d.]+\s*/\s*[\d.]+\s*=\s*\K[\d.]+' || echo "0")
    CUR_AVG_OUT=$(echo "${METRICS}" | grep -oP 'Avg\s*:\s*\K[\d.]+' || echo "N/A")

    if [[ "${THROUGHPUT}" == "0" || "${THROUGHPUT}" == "" ]]; then
        echo "  ⚠️ 无法解析吞吐，跳过此档"
        CURRENT_CON=$(( CURRENT_CON + 10 ))
        continue
    fi

    # 跟踪历史最高吞吐对应的指标（饱和后应报告峰值档，而非过载档）
    if [[ "${PEAK_THROUGHPUT}" == "0" ]] || \
       ${PYTHON} -c "exit(0 if float('${THROUGHPUT}') > float('${PEAK_THROUGHPUT}') else 1)" 2>/dev/null; then
        PEAK_THROUGHPUT="${THROUGHPUT}"
        PEAK_MAX_RPS="${CUR_MAX_RPS}"
        PEAK_AVG_OUT="${CUR_AVG_OUT}"
        PEAK_CON="${CURRENT_CON}"
    fi

    # ── 饱和判断（两段式步进）─────────────────────────────────
    if [[ "${PREV_THROUGHPUT}" == "0" ]]; then
        echo "  第一档（先验起点），继续翻倍"
        PREV_THROUGHPUT="${THROUGHPUT}"
        CURRENT_CON=$(( CURRENT_CON * 2 ))
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
        echo "   (峰值档: con=${PEAK_CON}, throughput=${PEAK_THROUGHPUT} tokens/s)"
        echo ""
        # ⚠️ 关键修复：饱和时应报告峰值档指标，而非过载档
        # 当吞吐下降时，当前档是过载档；峰值档才是真实能力上限
        MAX_RPS_EST="${PEAK_MAX_RPS}"
        AVG_OUT="${PEAK_AVG_OUT}"
        START_RPS=$(${PYTHON} -c "print(round(float('${MAX_RPS_EST}'), 4))" 2>/dev/null || echo "N/A")
        START_RPS=$(${PYTHON} -c "print(round(float('${MAX_RPS_EST}') * 1.2, 4))" 2>/dev/null || echo "N/A")

        cat > "${CHECKPOINT}" << EOF
# Phase 1 检查点 — guoxue-72b V2（4×H20）

| 指标 | 值 |
|------|-----|
| peak_decode_throughput | ${PEAK_THROUGHPUT} tokens/s |
| peak_concurrency | ${PEAK_CON} |
| avg_output_len | ${AVG_OUT} tokens |
| max_rps_estimate | ${MAX_RPS_EST} req/s |
| overload_concurrency | ${CURRENT_CON}（吞吐下降 ${INCREASE}%，已过载）|
| **Phase 2 起始 QPS** | **${START_RPS} req/s**（peak max_rps × 1.2）|

## 饱和确认
最后两档吞吐增幅 ${INCREASE}% < 1%，已饱和。
峰值吞吐出现在 con=${PEAK_CON}（${PEAK_THROUGHPUT} tokens/s），con=${CURRENT_CON} 过载。

## Phase 2 启动命令
\`\`\`bash
PEAK_RPS=${MAX_RPS_EST} START_RPS=${START_RPS} \\
  bash scripts/benchmark/run_phase2_auto_guoxue4h20.sh
\`\`\`
EOF
        echo "  检查点已写入: ${CHECKPOINT}"
        echo ""
        echo "  ▶ 下一步："
        echo "    PEAK_RPS=${MAX_RPS_EST} START_RPS=${START_RPS} \\"
        echo "      bash scripts/benchmark/run_phase2_auto_guoxue4h20.sh"
        break
    fi

    PREV_THROUGHPUT="${THROUGHPUT}"

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
