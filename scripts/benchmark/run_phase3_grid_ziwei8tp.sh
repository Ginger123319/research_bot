#!/bin/bash
set -e

OUTPUT_BASE="logs/ziwei-32b-8tp-phase3_20260319"
DATASET="datas/output_ziwei/xinghan-ziwei-32b-v1-1_selected_combined_3days_peak_poisson_100_stitched.csv"
URL="https://infer-test.geniuworks.com/infra-xinghan-ziwei-p32b-v1-test/v1/chat/completions"
TOKENIZER="/mnt/ai-llm/xinghan-ziwei-32b-v1"
TIME_LIMIT=2700

mkdir -p ${OUTPUT_BASE}

declare -a QPS_LIST=(0.474 0.7531 1.0321 1.3112)

echo "Phase 3 Grid — ziwei-32b 8TP"
echo "Grid: ${QPS_LIST[@]}"

for qps in ${QPS_LIST[@]}; do
  num_requests=$(python3 -c "print(int(${qps} * ${TIME_LIMIT} * 1.2))")
  
  echo "========== QPS ${qps} =========="
  
  .venv/bin/python3 -m llm_benchmark.benchmark.benchmark \
    --exp-name "phase3_qps${qps}" \
    --dataset-path "${DATASET}" \
    --url "${URL}" \
    --model "ignore-model-name" \
    --request-rate ${qps} \
    --num-requests ${num_requests} \
    --request-time-limit ${TIME_LIMIT} \
    --output-dir "${OUTPUT_BASE}/qps${qps}" \
    --tokenizer "${TOKENIZER}" \
    --max-completion-tokens 4096 \
    --no-kvcache \
    --shuffle
  
  echo "Done: QPS ${qps}"
done

echo "Phase 3 Complete"
