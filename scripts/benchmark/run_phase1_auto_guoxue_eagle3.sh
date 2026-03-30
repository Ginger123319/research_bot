#!/bin/bash
# Phase 1 自动饱和探测 — xinghan-guoxue-72b-v1-2-reason EAGLE3
#
# eagle3 投机解码（EAGLE3-3-1-4）；8×L20；V2 真实线上数据
# 从 con=40 起跳（vanilla 饱和点 con=30，eagle3 更快，预计饱和 ~45~55）
# 每档 300s（5min），档间强制冷却 900s（E2E ~300s 模型必须）
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_guoxue_eagle3.sh
#   INIT_CON=50 bash scripts/benchmark/run_phase1_auto_guoxue_eagle3.sh  # 续跑

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer-test.geniuworks.com/bazi-guoxue-eagle3-test/v1/chat/completions"
TARGET_MODEL="xinghan-guoxue-72b-v1-2-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv"
MAX_COMPLETION_TOKENS=4096

# Phase 1 时长参数
# avg_output_len ≈ 1386 tokens → est_e2e ≈ 14s（eagle3 快，保守取 100tok/s）
# 300s 内可完成 ~40×300/14 ≈ 860 条，足够统计吞吐
TIME_LIMIT_SECS=300

# ⚠️ CRITICAL：档位间冷却 900s（15min）
# eagle3 E2E P90 预计 ~120~180s，冷却不足 → 前档在途请求积压 → 吞吐振荡
COOLDOWN_SECS=900

AVG_OUTPUT_LEN=2142  # 来自 Phase 0 分析结果

# ── 初始并发 ─────────────────────────────────────────────────
# eagle3 比 vanilla 快约 47~53%，vanilla 饱和点 con=30
# → 预期 eagle3 饱和在 con=45~50，从 con=40 起跳（用户确认）
INIT_CON="${INIT_CON:-40}"

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/guoxue-v2-eagle3-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

DATASET_DATA_ROWS=$(( $(wc -l < "${DATASET_PATH}") - 1 ))

echo "========================================================"
echo "Phase 1 自动饱和探测 — guoxue-72b EAGLE3"
echo "  初始并发: ${INIT_CON}（vanilla 饱和点 30 × 1.5 = 45，取 40 起跳）"
echo "  每档时长: ${TIME_LIMIT_SECS}s，档间冷却: ${COOLDOWN_SECS}s"
echo "  endpoint: ${SERVER_URL}"
echo "  数据集: $(basename ${DATASET_PATH}) (${DATASET_DATA_ROWS} 条)"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
PREV_THROUGHPUT=0
MAX_ITERS=12

for iter in $(seq 1 ${MAX_ITERS}); do
    LEVEL_DIR="${OUTPUT_BASE}/con${CURRENT_CON}"

    # ── 计算 NUM_REQUESTS（按 Skill 推荐公式）──────────────────
    # 高并发下单请求实际速率 = 总吞吐/并发，远低于单卡峰值 100 t/s；分段估算：
    #   avg_out < 100  → 50 t/s/req；100~500 → 20 t/s/req；> 500 → 15 t/s/req
    # max_comp = CON × ceil(TIME_LIMIT / est_e2e)
    # NUM_REQUESTS = max_comp × 3（3× 安全系数）
    NUM_REQUESTS=$(${PYTHON} -c "
import math
avg_out  = ${AVG_OUTPUT_LEN}
if avg_out < 100:
    per_req_rate = 50
elif avg_out < 500:
    per_req_rate = 20
else:
    per_req_rate = 15
est_e2e  = max(0.5, avg_out / per_req_rate)
max_comp = ${CURRENT_CON} * math.ceil(${TIME_LIMIT_SECS} / est_e2e)
nr       = max(int(max_comp * 3), ${CURRENT_CON} * 5)
# 不超过数据集行数
print(min(nr, ${DATASET_DATA_ROWS}))
")

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 档  并发=${CURRENT_CON}  num_requests=${NUM_REQUESTS}"
    echo "  开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "────────────────────────────────────────────────────────"

    if [[ -d "${LEVEL_DIR}" ]] && ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ⏭ 已有结果，跳过执行（直接分析）"
    else
        mkdir -p "${LEVEL_DIR}"
        cd "${LLM_BENCHMARK_ROOT}"
        "${PYTHON}" -m llm_benchmark.benchmark.benchmark \
            --exp-name       "guoxue_eagle3_phase1_con${CURRENT_CON}" \
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

    echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')"

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
    if [[ "${THROUGHPUT}" == "0" || "${THROUGHPUT}" == "" ]]; then
        echo "  ⚠️ 无法解析吞吐，跳过此档"
        CURRENT_CON=$(( CURRENT_CON + 10 ))
        # 档间冷却（仍然需要）
        echo "  冷却 ${COOLDOWN_SECS}s ..."
        sleep ${COOLDOWN_SECS}
        continue
    fi

    # ── 饱和判断 ─────────────────────────────────────────────
    if [[ "${PREV_THROUGHPUT}" == "0" ]]; then
        echo "  第一档，继续翻倍"
        PREV_THROUGHPUT="${THROUGHPUT}"
        CURRENT_CON=$(( CURRENT_CON * 2 ))
        echo "  冷却 ${COOLDOWN_SECS}s ..."
        sleep ${COOLDOWN_SECS}
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
    DECLINED=$(${PYTHON} -c "print('yes' if float('${INCREASE}') < 0.0 else 'no')")

    if [[ "${SATURATED}" == "yes" || "${DECLINED}" == "yes" ]]; then
        echo ""
        echo "✅ 饱和确认！增幅 < 1% 或吞吐下降，停止探测"
        echo ""
        # ⚠️ 注意：analyze 输出格式为 "max_rps_estimate = 546.9 / 2210.7 = 0.2474 req/s"
        # 正确方法：用 tokens/s 和 avg_output_len 直接计算，不依赖 analyze 的 max_rps_estimate 行
        THROUGHPUT_PEAK="${PREV_THROUGHPUT}"  # 饱和档吞吐即上一档（峰值档）
        AVG_OUT_MEASURED=$(echo "${METRICS}" | grep -oP 'Avg\s*:\s*\K[\d.]+' || echo "N/A")
        # 若 AVG_OUT_MEASURED 提取失败则从 METRICS 中取另一个格式
        if [[ "${AVG_OUT_MEASURED}" == "N/A" ]]; then
            AVG_OUT_MEASURED=$(echo "${METRICS}" | grep -oP 'avg_output_len\s*[=:]\s*\K[\d.]+' || echo "N/A")
        fi
        MAX_RPS_EST=$(${PYTHON} -c "
t=float('${THROUGHPUT_PEAK}'); a=float('${AVG_OUT_MEASURED}') if '${AVG_OUT_MEASURED}' != 'N/A' else 1
print(round(t/a, 4))" 2>/dev/null || echo "N/A")
        START_RPS=$(${PYTHON} -c "print(round(float('${MAX_RPS_EST}') * 1.2, 4))" 2>/dev/null || echo "N/A")

        cat > "${CHECKPOINT}" << EOF
# Phase 1 检查点 — guoxue-72b EAGLE3（8×L20）

| 指标 | 值 |
|------|-----|
| peak_decode_throughput | ${THROUGHPUT_PEAK} tokens/s |
| avg_output_len | ${AVG_OUT_MEASURED} tokens |
| max_rps_estimate | ${MAX_RPS_EST} req/s |
| max_running_concurrency | $(( CURRENT_CON / 2 ))（峰值档，饱和确认档为 ${CURRENT_CON}）|
| **Phase 2 起始 QPS** | **${START_RPS} req/s**（max_rps × 1.2）|

## 饱和确认
最后两档吞吐增幅 ${INCREASE}%，已确认饱和。

## Phase 2 启动命令
\`\`\`bash
PEAK_RPS=${MAX_RPS_EST} START_RPS=${START_RPS} \\
  bash scripts/benchmark/run_phase2_auto_guoxue_eagle3.sh
\`\`\`
EOF
        echo "  检查点已写入: ${CHECKPOINT}"
        echo ""
        echo "  ▶ 下一步："
        echo "    PEAK_RPS=${MAX_RPS_EST} START_RPS=${START_RPS} \\"
        echo "      bash scripts/benchmark/run_phase2_auto_guoxue_eagle3.sh"
        break
    fi

    PREV_THROUGHPUT="${THROUGHPUT}"

    if [[ "${NEAR_SAT}" == "yes" ]]; then
        echo "  接近饱和（1%~10%），切换 +10 线性步进"
        NEXT_CON=$(( CURRENT_CON + 10 ))
    else
        echo "  未饱和（>10%），继续翻倍"
        NEXT_CON=$(( CURRENT_CON * 2 ))
    fi
    CURRENT_CON=${NEXT_CON}

    # ⚠️ 档间冷却：长输出模型必须等待前档在途请求排空
    echo "  冷却 ${COOLDOWN_SECS}s（防止测试污染）..."
    sleep ${COOLDOWN_SECS}
done

echo ""
echo "========================================================"
echo "Phase 1 完成，输出目录: ${OUTPUT_BASE}"
echo "========================================================"
