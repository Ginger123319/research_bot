#!/bin/bash
# Phase 1 自动饱和探测循环 — xinghan-guoxue-72b-v1-2-reason Eagle3 × 4×H20
#
# 新 endpoint: infra-opti-xinghan-guoxue-p72b-v12-reason（Eagle3 投机解码）
# 硬件与 vanilla 4×H20 相同，先验饱和点 con≈60~80，从 con=60 起跳。
#
# 关键参数说明：
#   AVG_OUTPUT_LEN_PHASE0 = 2204 tokens（Phase 1 实测值；Phase 0 原始值 1386 有数据缺陷，见注释）
#   用于 max_rps_estimate = decode_throughput / avg_output_len_phase0
#   ⚠️ Phase 0 数据质量检查：old_response 未含 ai_deep_content，缺陷已知，改用 Phase 1 实测值
#
# 用法：
#   bash scripts/benchmark/run_phase1_auto_guoxue_eagle3_4h20.sh
#   INIT_CON=80 bash scripts/benchmark/run_phase1_auto_guoxue_eagle3_4h20.sh  # 续跑

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-opti-xinghan-guoxue-p72b-v12-reason/v1/chat/completions"
TARGET_MODEL="infra-opti-xinghan-guoxue-p72b-v12-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv"
MAX_COMPLETION_TOKENS=4096

# ── avg_output_len（用于 max_rps_estimate 计算）──────────────────────────
# ⚠️ Phase 0 数据质量检查结论（2026-03-24）：
#   Phase 0 原始值 = 1386 tokens，但数据集 old_response 有已知结构性缺陷：
#     - 未前置 ai_deep_content（推理链 ~818 tokens 缺失）
#     - <con> 未转换为 ## 结论（格式与当前模型输出不一致）
#   Phase 0 不可信，改用 Phase 1 实测 avg_output_len（见 qps-peak-finder SKILL §Phase 0 质量检查）
#
# Phase 1 实测值（con=260 档，2026-03-23）= 2204.1 tokens
#   验证：1386 vs 2204 偏差 = +59%，远超 20% 阈值，数据缺陷已确认
AVG_OUTPUT_LEN_PHASE0=2204   # 使用 Phase 1 实测值（Phase 0 数据有缺陷）

# ── 时长与冷却（avg_output_len=2204 → DURATION=max(300,5510)≈5400s, COOLDOWN=max(60,1102)≈1200s）──
TIME_LIMIT_SECS=5400   # max(300, int(2204 * 2.5)) = 5510 → 取 5400（1.5h，整数小时）
COOLDOWN_SECS=1200     # max(60, int(2204 / 2)) = 1102 → 取 1200（20min，稍保守）

# ── 初始并发 ────────────────────────────────────────────────────
# 4×H20 vanilla 饱和点在 con=60，Eagle3 加速后饱和点≥60，从 con=60 起跳跳过低档位爬坡
INIT_CON="${INIT_CON:-60}"

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/guoxue-v2-eagle3-4h20-phase1_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase1_checkpoint.md"
mkdir -p "${OUTPUT_BASE}"

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
echo "Phase 1 自动饱和探测 — guoxue-72b EAGLE3（4×H20）"
echo "  初始并发: ${INIT_CON}（先验加速，跳过低档位爬坡）"
echo "  每档时长: ${TIME_LIMIT_SECS}s  冷却: ${COOLDOWN_SECS}s"
echo "  avg_output_len_phase0: ${AVG_OUTPUT_LEN_PHASE0} tokens（权威值，用于 max_rps 计算）"
echo "  数据集: $(basename ${DATASET_PATH}) (${DATASET_DATA_ROWS} 条)"
echo "  endpoint: ${SERVER_URL}"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

CURRENT_CON="${INIT_CON}"
PREV_THROUGHPUT=0
PEAK_THROUGHPUT=0
PEAK_CON=0
PEAK_AVG_OUT_MEASURED="N/A"   # Phase 1 实测值（仅参考）
MAX_ITERS=15

for iter in $(seq 1 ${MAX_ITERS}); do
    LEVEL_DIR="${OUTPUT_BASE}/con${CURRENT_CON}"

    # ⚠️ NUM_REQUESTS 必须基于 est_e2e 推算，不能硬编码
    # 核心原则：high-concurrency 下单请求速率 = 总吞吐/并发，72B con=60 实测约 18 t/s/请求
    # 先验 est_e2e = vanilla 4H20 实测 mean_e2e = 93.31s（Eagle3 只会更快，取保守上界）
    # 分段 fallback：avg_out > 500 → 15 t/s（实测 72B 约 17-18 t/s，取 15 保守）
    NUM_REQUESTS=$(${PYTHON} -c "
import math, os
avg_out = max(1, ${AVG_OUTPUT_LEN_PHASE0})
# 先验 E2E（vanilla 4H20 实测 mean_e2e=93.31s，Eagle3 ≤ vanilla）
known_e2e = float(os.environ.get('EST_E2E', '93.31'))
if avg_out < 100:
    per_req_rate = 50
elif avg_out < 500:
    per_req_rate = 20
else:
    per_req_rate = 15   # 72B+ 大模型
est_e2e = max(5.0, min(known_e2e, avg_out / per_req_rate))
max_comp = ${CURRENT_CON} * math.ceil(${TIME_LIMIT_SECS} / est_e2e)
print(max(int(max_comp * 3), ${CURRENT_CON} * 5))
")

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
            --exp-name       "guoxue_eagle3_4h20_phase1_con${CURRENT_CON}" \
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

    # ── 档位间冷却 ──────────────────────────────────────────────
    echo "  冷却 ${COOLDOWN_SECS}s（排空在途请求，防止测试污染）..."
    sleep "${COOLDOWN_SECS}"

    # ── 分析本档结果 ──────────────────────────────────────────
    METRICS=$(${PYTHON} "${ANALYZE}" \
        --phase 1 \
        --dir "${LEVEL_DIR}" \
        --ttfs-p90-limit 1.5 \
        --e2e-p90-limit 180.0 \
        --avg-output-len-phase0 "${AVG_OUTPUT_LEN_PHASE0}" \
        2>/dev/null || echo "PARSE_ERROR")

    echo "${METRICS}"

    THROUGHPUT=$(echo "${METRICS}" | grep -oP 'decode_throughput\s*[=:]\s*\K[\d.]+' || echo "0")
    # avg_output_len 实测值（仅供参考，与 Phase 0 差异 >20% 时提示模型行为变化）
    AVG_OUT_MEASURED=$(echo "${METRICS}" | grep -oP 'Avg\s*:\s*\K[\d.]+' || echo "N/A")
    # max_rps 从 analyze 输出 "A / B = C req/s" 中提取 C（最终结果值）
    CUR_MAX_RPS_FROM_ANALYZE=$(echo "${METRICS}" | grep -oP 'max_rps_estimate\s*=\s*[\d.]+\s*/\s*[\d.]+\s*=\s*\K[\d.]+' || echo "0")

    if [[ "${THROUGHPUT}" == "0" || "${THROUGHPUT}" == "" ]]; then
        echo "  ⚠️ 无法解析吞吐，跳过此档"
        CURRENT_CON=$(( CURRENT_CON + 10 ))
        continue
    fi

    # ⚠️ max_rps_estimate 用 Phase 0 权威值重新计算（不依赖 analyze 的内部计算）
    MAX_RPS_EST=$(${PYTHON} -c "
t = float('${THROUGHPUT}')
a = float('${AVG_OUTPUT_LEN_PHASE0}')
print(round(t / a, 4))
" 2>/dev/null || echo "0")

    echo "  max_rps_estimate (Phase0 分母) = ${THROUGHPUT} / ${AVG_OUTPUT_LEN_PHASE0} = ${MAX_RPS_EST} req/s"
    if [[ "${AVG_OUT_MEASURED}" != "N/A" ]]; then
        DEV_PCT=$(${PYTHON} -c "
a0=${AVG_OUTPUT_LEN_PHASE0}; am=float('${AVG_OUT_MEASURED}')
print(f'{abs(am-a0)/a0*100:.1f}')
" 2>/dev/null || echo "?")
        echo "  avg_output_len: Phase0=${AVG_OUTPUT_LEN_PHASE0} tokens | 实测=${AVG_OUT_MEASURED} tokens | 偏差=${DEV_PCT}%"
        if ${PYTHON} -c "exit(0 if float('${DEV_PCT:-0}') > 20 else 1)" 2>/dev/null; then
            echo "  ⚠️ 实测 avg_output_len 偏差 >20%，可能模型行为已变化（Eagle3 生成更长内容）"
        fi
    fi

    # 跟踪历史峰值
    if [[ "${PEAK_THROUGHPUT}" == "0" ]] || \
       ${PYTHON} -c "exit(0 if float('${THROUGHPUT}') > float('${PEAK_THROUGHPUT}') else 1)" 2>/dev/null; then
        PEAK_THROUGHPUT="${THROUGHPUT}"
        PEAK_MAX_RPS="${MAX_RPS_EST}"
        PEAK_AVG_OUT_MEASURED="${AVG_OUT_MEASURED}"
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
        echo "   峰值档: con=${PEAK_CON}, throughput=${PEAK_THROUGHPUT} tokens/s"
        echo ""

        START_RPS=$(${PYTHON} -c "print(round(float('${PEAK_MAX_RPS}') * 1.2, 4))" 2>/dev/null || echo "N/A")

        cat > "${CHECKPOINT}" << EOF
# Phase 1 检查点 — guoxue-72b EAGLE3（4×H20）

| 指标 | 值 |
|------|-----|
| peak_decode_throughput | ${PEAK_THROUGHPUT} tokens/s |
| peak_concurrency | ${PEAK_CON} |
| avg_output_len (Phase 0) | ${AVG_OUTPUT_LEN_PHASE0} tokens ← old_response 权威统计，用于 max_rps 计算 |
| avg_output_len (Phase 1 实测) | ${PEAK_AVG_OUT_MEASURED} tokens ← 仅供参考，偏差 >20% 说明模型行为变化 |
| max_rps_estimate | ${PEAK_MAX_RPS} req/s（= ${PEAK_THROUGHPUT} / ${AVG_OUTPUT_LEN_PHASE0}，Phase 0 分母）|
| overload_concurrency | ${CURRENT_CON}（吞吐增幅 ${INCREASE}%，已过载）|
| **Phase 2 起始 QPS** | **${START_RPS} req/s**（peak max_rps × 1.2）|

## 饱和确认
最后两档吞吐增幅 ${INCREASE}% < 1%，已饱和。
峰值吞吐出现在 con=${PEAK_CON}（${PEAK_THROUGHPUT} tokens/s），con=${CURRENT_CON} 为过载档。

## Phase 2 启动命令
\`\`\`bash
PEAK_RPS=${PEAK_MAX_RPS} START_RPS=${START_RPS} \\
  bash scripts/benchmark/run_phase2_auto_guoxue_eagle3_4h20.sh
\`\`\`
EOF
        echo "  检查点已写入: ${CHECKPOINT}"
        echo ""
        echo "  ▶ 下一步："
        echo "    PEAK_RPS=${PEAK_MAX_RPS} START_RPS=${START_RPS} \\"
        echo "      bash scripts/benchmark/run_phase2_auto_guoxue_eagle3_4h20.sh"
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
