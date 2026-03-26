#!/bin/bash
# Phase 2a 自动收敛循环 — xinghan-guoxue-72b-v1-2-reason 4×H20
#
# SLA: TTFS P90 ≤ 1.5s, E2E P90 ≤ 180s
# Bracket 几何中点精查，宽度 < 3% 时收敛。
#
# 用法：
#   PEAK_RPS=<peak_rps> START_RPS=<max_rps×1.2> bash scripts/benchmark/run_phase2_auto_guoxue4h20.sh
#   续跑：PEAK_RPS=X START_RPS=X INIT_LO=X INIT_HI=X bash ...

set -euo pipefail

PROJECT_DIR="/mnt/ai-infra/users/wnd/workspace/execute/guofan"
LLM_BENCHMARK_ROOT="${PROJECT_DIR}/third_party/speculative-decoding-benchmark/3rdparty/llm-benchmark"
PYTHON="${PROJECT_DIR}/.venv/bin/python3"
ANALYZE="${PROJECT_DIR}/scripts/analysis/analyze_peak_finder.py"

# ── 模型参数 ────────────────────────────────────────────────
SERVER_URL="https://infer.geniuworks.com/infra-xinghan-guoxue-p72b-v12-reason/v1/chat/completions"
TARGET_MODEL="infra-xinghan-guoxue-p72b-v12-reason"
TOKENIZER="/mnt/ai-llm/l83v2-G1-400"
DATASET_PATH="${PROJECT_DIR}/datas/output_guoxue_v2/xinghan-guoxue-72b-v1-2-reason_selected_combined_2days_peak_poisson_256_stitched.csv"
MAX_COMPLETION_TOKENS=4096
DURATION_SECS=3600    # 1h/档（avg_output_len ≈ 1386 → max(1200, 3465) → 取整 3600）
COOLDOWN_SECS=900     # 15min 冷却（E2E P90 ~300s 的模型，需充分排空）

# ── SLA 阈值 ─────────────────────────────────────────────────
TTFS_P90_LIMIT=1.5    # 1500ms
E2E_P90_LIMIT=180.0   # 180s（V2 更新）

# ── Phase 1 输出（由调用方传入）────────────────────────────────
PEAK_RPS="${PEAK_RPS:-0}"
START_RPS="${START_RPS:-}"

if [[ -z "${START_RPS}" && "${PEAK_RPS}" == "0" ]]; then
    echo "❌ 请先完成 Phase 1，然后设置环境变量："
    echo "   PEAK_RPS=<peak_rps>  START_RPS=<max_rps×1.2>  bash $0"
    exit 1
fi

TIMESTAMP="$(date +%Y%m%d_%H%M)"
OUTPUT_BASE="${PROJECT_DIR}/logs/guoxue-v2-h20-phase2_${TIMESTAMP}"
CHECKPOINT="${OUTPUT_BASE}/phase2_checkpoint.md"
PHASE3_SCRIPT="${PROJECT_DIR}/scripts/benchmark/run_phase3_grid_guoxue4h20.sh"
mkdir -p "${OUTPUT_BASE}"

# bracket 区间（可从环境变量覆盖续跑）
LO_RPS="${INIT_LO:-}"
HI_RPS="${INIT_HI:-}"
LAST_PASS_RPS=""   # 追踪最后一次 PASS 档，供 EXIT trap 使用

PRODUCTION_RPS=0.05   # 安全托底（H20 首次部署，无 Grafana 生产数据）

# ── EXIT trap：兜底写入 checkpoint ───────────────────────────────
write_exit_checkpoint() {
    if [[ -f "${CHECKPOINT}" ]]; then return; fi
    echo ""
    echo "⚠️  [EXIT_TRAP] 脚本退出，写入兜底 checkpoint..."
    if [[ -n "${LAST_PASS_RPS:-}" ]]; then
        local width_str="—"
        if [[ -n "${HI_RPS:-}" ]]; then
            width_str=$(${PYTHON} -c "
lo=float('${LAST_PASS_RPS}'); hi=float('${HI_RPS}')
print(f'{(hi-lo)/lo*100:.2f}%')" 2>/dev/null || echo "—")
        fi
        cat > "${CHECKPOINT}" << EOF
# Phase 2 检查点 — guoxue-72b V2（4×H20）[EXIT_TRAP]

> ⚠️ 脚本意外退出（bracket 未收敛至 <3%），以最后 PASS 档为 ideal_rps。

| 指标 | 值 |
|------|-----|
| **ideal_rps** | **${LAST_PASS_RPS} req/s** |
| **ideal_rpm** | $(${PYTHON} -c "print(f'{float(\"${LAST_PASS_RPS}\")*60:.1f}')") RPM |
| hi_rps（首个失败）| ${HI_RPS:-未知} req/s |
| bracket 宽度 | ${width_str}（未收敛）|
| 来源 | EXIT_TRAP（Round ${iter:-?} 后退出）|
| SLA | TTFS P90 ≤ ${TTFS_P90_LIMIT}s，E2E P90 ≤ ${E2E_P90_LIMIT}s |

## Phase 3 启动命令
\`\`\`bash
IDEAL_RPS=${LAST_PASS_RPS} PRODUCTION_RPS=${PRODUCTION_RPS} \\
  bash scripts/benchmark/run_phase3_grid_guoxue4h20.sh
\`\`\`
EOF
        echo "  ✅ 兜底 checkpoint 已写入: ${CHECKPOINT}"
    else
        echo "# Phase 2 无任何 PASS 结果 [EXIT_TRAP — 请检查后重跑]" \
            > "${OUTPUT_BASE}/phase2_no_pass.md"
        echo "  ❌ 无任何 PASS 轮次，请检查服务状态后重跑 Phase 2"
    fi
}
trap write_exit_checkpoint EXIT

echo "========================================================"
echo "Phase 2a 自动收敛 — guoxue-72b V2（4×H20）"
echo "  peak_rps=${PEAK_RPS}  start_rps=${START_RPS}"
echo "  duration=${DURATION_SECS}s  cooldown=${COOLDOWN_SECS}s"
echo "  SLA: TTFS P90≤${TTFS_P90_LIMIT}s  E2E P90≤${E2E_P90_LIMIT}s"
echo "  bracket: LO=${LO_RPS:-未知}  HI=${HI_RPS:-未知}"
echo "  production_rps=${PRODUCTION_RPS}（托底）"
echo "  输出目录: ${OUTPUT_BASE}"
echo "========================================================"

# 设置起始 RPS
if [[ -n "${LO_RPS}" || -n "${HI_RPS}" ]]; then
    CURRENT_RPS=$(${PYTHON} -c "
import math
lo = float('${LO_RPS}') if '${LO_RPS}' else None
hi = float('${HI_RPS}') if '${HI_RPS}' else None
if lo and hi:
    print(f'{math.sqrt(lo * hi):.4f}')
elif lo:
    print(f'{lo * 1.1:.4f}')
else:
    print('${START_RPS}')
")
else
    CURRENT_RPS="${START_RPS}"
fi

MAX_ITERS=20

for iter in $(seq 1 ${MAX_ITERS}); do
    RPS_TAG=$(printf "%.4f" "${CURRENT_RPS}")
    LEVEL_DIR="${OUTPUT_BASE}/rps${RPS_TAG}"
    NUM_PROMPTS=$(${PYTHON} -c "import math; print(math.ceil(float('${CURRENT_RPS}') * ${DURATION_SECS} * 1.1))")

    echo ""
    echo "────────────────────────────────────────────────────────"
    echo "  第 ${iter} 轮  RPS=${CURRENT_RPS}  num_prompts=${NUM_PROMPTS}"
    echo "  bracket: LO=${LO_RPS:-未知}  HI=${HI_RPS:-未知}"
    echo "────────────────────────────────────────────────────────"

    if [[ -d "${LEVEL_DIR}" ]] && ls "${LEVEL_DIR}"/*.csv 2>/dev/null | grep -qv "argv"; then
        echo "  ⏭ 已有结果，跳过执行"
    else
        mkdir -p "${LEVEL_DIR}"
        cd "${LLM_BENCHMARK_ROOT}"
        "${PYTHON}" -m llm_benchmark.benchmark.benchmark \
            --exp-name       "guoxue_v2_h20_phase2_rps${RPS_TAG}" \
            --dataset-path   "${DATASET_PATH}" \
            --url            "${SERVER_URL}" \
            --model          "${TARGET_MODEL}" \
            --request-rate   "${CURRENT_RPS}" \
            --num-requests   "${NUM_PROMPTS}" \
            --request-time-limit "${DURATION_SECS}" \
            --output-dir     "${LEVEL_DIR}" \
            --no-kvcache \
            --shuffle \
            --tokenizer      "${TOKENIZER}" \
            --max-completion-tokens "${MAX_COMPLETION_TOKENS}" \
            || echo "⚠️ rps=${CURRENT_RPS} 异常，记录后继续"
        cd "${PROJECT_DIR}"
    fi

    # ── 分析本档 SLA ──────────────────────────────────────────
    METRICS=$(${PYTHON} "${ANALYZE}" \
        --phase 2 \
        --dir "${LEVEL_DIR}" \
        --ttfs-p90-limit "${TTFS_P90_LIMIT}" \
        --e2e-p90-limit "${E2E_P90_LIMIT}" \
        2>/dev/null || echo "PARSE_ERROR")

    echo "${METRICS}"

    SLA_PASS=$(echo "${METRICS}" | grep -oP '\[SLA_(PASS|FAIL)\]' | grep -oP 'PASS|FAIL' || echo "UNKNOWN")
    echo "  SLA 状态: ${SLA_PASS}"

    # ── 更新 bracket ─────────────────────────────────────────
    if [[ "${SLA_PASS}" == "PASS" ]]; then
        if [[ -z "${LO_RPS}" ]] || ${PYTHON} -c "exit(0 if float('${CURRENT_RPS}') > float('${LO_RPS}') else 1)" 2>/dev/null; then
            LO_RPS="${CURRENT_RPS}"
            LAST_PASS_RPS="${CURRENT_RPS}"
            echo "  LO 更新: ${LO_RPS}"
        fi
    elif [[ "${SLA_PASS}" == "FAIL" ]]; then
        if [[ -z "${HI_RPS}" ]] || ${PYTHON} -c "exit(0 if float('${CURRENT_RPS}') < float('${HI_RPS}') else 1)" 2>/dev/null; then
            HI_RPS="${CURRENT_RPS}"
            echo "  HI 更新: ${HI_RPS}"
        fi
    fi

    # ── 收敛判断 & 下一档计算（bracket 更新后重新计算，不复用 analyze 的 NEXT_RPS）─
    if [[ -n "${LO_RPS}" && -n "${HI_RPS}" ]]; then
        CONVERGED=$(${PYTHON} -c "
lo=float('${LO_RPS}'); hi=float('${HI_RPS}')
print('yes' if (hi-lo)/lo < 0.03 else 'no')
")
        if [[ "${CONVERGED}" == "yes" ]]; then
            echo ""
            echo "✅ bracket 收敛！宽度 < 3%，ideal_rps = ${LO_RPS}"
            echo ""
            cat > "${CHECKPOINT}" << EOF
# Phase 2 检查点 — guoxue-72b V2（4×H20）收敛

| 指标 | 值 |
|------|-----|
| **ideal_rps** | **${LO_RPS} req/s** |
| **ideal_rpm** | $(${PYTHON} -c "print(f'{float(\"${LO_RPS}\")*60:.1f}')") RPM |
| hi_rps（首个失败）| ${HI_RPS} req/s |
| bracket 宽度 | $(${PYTHON} -c "lo=float('${LO_RPS}');hi=float('${HI_RPS}');print(f'{(hi-lo)/lo*100:.2f}%')") |
| SLA | TTFS P90 ≤ ${TTFS_P90_LIMIT}s，E2E P90 ≤ ${E2E_P90_LIMIT}s |

## Phase 3 启动命令
\`\`\`bash
IDEAL_RPS=${LO_RPS} PRODUCTION_RPS=${PRODUCTION_RPS} \\
  bash scripts/benchmark/run_phase3_grid_guoxue4h20.sh
\`\`\`
EOF
            echo "  ▶ 下一步："
            echo "    IDEAL_RPS=${LO_RPS} PRODUCTION_RPS=${PRODUCTION_RPS} \\"
            echo "      bash scripts/benchmark/run_phase3_grid_guoxue4h20.sh"
            break
        fi

        # bracket 已建立，几何中点（在 LO/HI 更新后重新计算，不复用 analyze 输出值）
        CURRENT_RPS=$(${PYTHON} -c "import math; print(f'{math.sqrt(float(\"${LO_RPS}\")*float(\"${HI_RPS}\")):.4f}')")
        echo "  ▶ bracket 几何中点（重新计算）: ${CURRENT_RPS}"

    else
        # bracket 未建立，从 analyze 建议读取下一档
        NEXT_BY_ANALYZE=$(echo "${METRICS}" | grep -oP '\[NEXT_RPS=\K[\d.]+' || echo "")
        if [[ -n "${NEXT_BY_ANALYZE}" ]]; then
            CURRENT_RPS="${NEXT_BY_ANALYZE}"
            echo "  ▶ 比例步进（无 bracket）: ${CURRENT_RPS}"
        else
            if [[ "${SLA_PASS}" == "PASS" ]]; then
                CURRENT_RPS=$(${PYTHON} -c "print(f'{float(\"${CURRENT_RPS}\")*1.1:.4f}')")
            else
                CURRENT_RPS=$(${PYTHON} -c "print(f'{float(\"${PEAK_RPS}\")*0.8:.4f}')")
            fi
            echo "  ▶ fallback 步进: ${CURRENT_RPS}"
        fi

        # production_rps 托底
        BELOW_PROD=$(${PYTHON} -c "print('yes' if float('${CURRENT_RPS}') < ${PRODUCTION_RPS} else 'no')")
        if [[ "${BELOW_PROD}" == "yes" ]]; then
            echo "  ⚠️ 下一档低于 production_rps（${PRODUCTION_RPS}），托底 ideal_rps = production_rps"
            LO_RPS="${PRODUCTION_RPS}"
            LAST_PASS_RPS="${PRODUCTION_RPS}"
            cat > "${CHECKPOINT}" << EOF
# Phase 2 检查点 — guoxue-72b V2（4×H20）[PRODUCTION_FLOOR]

> ⚠️ 所有探测档均 FAIL，以 production_rps 托底。

| 指标 | 值 |
|------|-----|
| **ideal_rps** | **${PRODUCTION_RPS} req/s** |
| **ideal_rpm** | $(${PYTHON} -c "print(f'{float(\"${PRODUCTION_RPS}\")*60:.1f}')") RPM |
| 来源 | PRODUCTION_FLOOR（托底）|
| SLA | TTFS P90 ≤ ${TTFS_P90_LIMIT}s，E2E P90 ≤ ${E2E_P90_LIMIT}s |

## Phase 3 启动命令
\`\`\`bash
IDEAL_RPS=${PRODUCTION_RPS} PRODUCTION_RPS=${PRODUCTION_RPS} \\
  bash scripts/benchmark/run_phase3_grid_guoxue4h20.sh
\`\`\`
EOF
            echo "  ▶ 下一步："
            echo "    IDEAL_RPS=${PRODUCTION_RPS} PRODUCTION_RPS=${PRODUCTION_RPS} \\"
            echo "      bash scripts/benchmark/run_phase3_grid_guoxue4h20.sh"
            break
        fi
    fi

    # ── 档间冷却 ─────────────────────────────────────────────
    echo "  冷却 ${COOLDOWN_SECS}s..."
    sleep ${COOLDOWN_SECS}
done

echo ""
echo "========================================================"
echo "Phase 2 完成，输出目录: ${OUTPUT_BASE}"
echo "========================================================"
