#!/usr/bin/env bash
# benchmark.sh — Lambda Power Tuning: test v1 and v2 at 128 / 256 / 512 / 1024 MB
#
# Usage:
#   bash scripts/benchmark.sh [--region us-east-1] [--invocations 5]
#
# Prerequisites:
#   - terraform apply completed (functions deployed)
#   - S3 seeded (scripts/seed_s3.py run)
#   - AWS CLI configured
#   - jq installed
#
# Output:
#   - Per-invocation timing printed to stdout
#   - results/benchmark_results.json written with full data
#   - results/summary.txt with the comparison table

set -euo pipefail

REGION="us-east-1"
INVOCATIONS=5
MEMORY_SIZES=(128 256 512 1024)

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)       REGION="$2";      shift 2 ;;
    --invocations)  INVOCATIONS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Resolve function names from Terraform outputs
TF_DIR="$(dirname "$0")/../terraform"
V1_FUNCTION=$(terraform -chdir="$TF_DIR" output -raw lambda_v1_name 2>/dev/null)
V2_FUNCTION=$(terraform -chdir="$TF_DIR" output -raw lambda_v2_name 2>/dev/null)

if [[ -z "$V1_FUNCTION" || -z "$V2_FUNCTION" ]]; then
  echo "ERROR: Could not read function names from Terraform outputs."
  echo "       Run 'terraform apply' inside the terraform/ directory first."
  exit 1
fi

RESULTS_DIR="$(dirname "$0")/../results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/benchmark_results.json"
SUMMARY_FILE="$RESULTS_DIR/summary.txt"

# Lambda pricing (us-east-1, May 2026)
# $0.0000166667 per GB-second; $0.20 per 1M requests
PRICE_PER_GB_SEC=0.0000166667
PRICE_PER_REQUEST=0.0000002

echo "[]" > "$RESULTS_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# Helper: invoke once, return billed_duration_ms and init_duration_ms
# ─────────────────────────────────────────────────────────────────────────────
invoke_once() {
  local fn="$1"
  local out
  out=$(mktemp)

  local response
  response=$(aws lambda invoke \
    --function-name "$fn" \
    --payload '{}' \
    --log-type Tail \
    --region "$REGION" \
    --cli-binary-format raw-in-base64-out \
    --output json \
    "$out" 2>&1)

  local log_b64
  log_b64=$(echo "$response" | jq -r '.LogResult // ""')
  local log
  log=$(echo "$log_b64" | base64 --decode 2>/dev/null || true)

  local billed
  billed=$(echo "$log" | grep -oP 'Billed Duration: \K[0-9]+' || echo "0")
  local init
  init=$(echo "$log" | grep -oP 'Init Duration: \K[0-9.]+' || echo "0")
  local max_mem
  max_mem=$(echo "$log" | grep -oP 'Max Memory Used: \K[0-9]+' || echo "0")

  rm -f "$out"
  echo "${billed},${init},${max_mem}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: cost for one invocation
#   cost = (memory_mb/1024) * (billed_ms/1000) * price_per_gb_sec + request_price
# ─────────────────────────────────────────────────────────────────────────────
calc_cost() {
  local mem_mb="$1"
  local billed_ms="$2"
  echo "scale=8; ($mem_mb/1024) * ($billed_ms/1000) * $PRICE_PER_GB_SEC + $PRICE_PER_REQUEST" | bc
}

# ─────────────────────────────────────────────────────────────────────────────
# Run benchmark for one function at one memory size
# ─────────────────────────────────────────────────────────────────────────────
run_at_memory() {
  local fn="$1"
  local label="$2"
  local mem="$3"

  echo ""
  echo "▶ [$label] memory=${mem}MB — updating config..."
  aws lambda update-function-configuration \
    --function-name "$fn" \
    --memory-size "$mem" \
    --region "$REGION" \
    --output json > /dev/null

  # Wait for the update to propagate
  aws lambda wait function-updated --function-name "$fn" --region "$REGION"

  local total_billed=0
  local cold_start="n/a"
  local min_billed=999999
  local max_billed=0

  for run in $(seq 1 "$INVOCATIONS"); do
    echo -n "  invocation $run/$INVOCATIONS ... "
    result=$(invoke_once "$fn")
    billed=$(echo "$result" | cut -d',' -f1)
    init=$(echo "$result"   | cut -d',' -f2)
    maxmem=$(echo "$result" | cut -d',' -f3)

    # First invocation captures cold start
    if [[ $run -eq 1 && "$init" != "0" && -n "$init" ]]; then
      cold_start="${init}ms"
    fi

    total_billed=$((total_billed + billed))
    [[ $billed -lt $min_billed ]] && min_billed=$billed
    [[ $billed -gt $max_billed ]] && max_billed=$billed

    cost=$(calc_cost "$mem" "$billed")
    echo "billed=${billed}ms  init=${init}ms  maxMem=${maxmem}MB  cost=\$${cost}"
  done

  local avg_billed=$(echo "scale=0; $total_billed / $INVOCATIONS" | bc)
  local avg_cost=$(calc_cost "$mem" "$avg_billed")
  local warm_billed=$((min_billed))  # min = best warm run

  echo "  ── avg=${avg_billed}ms  min=${min_billed}ms  max=${max_billed}ms  cold_start=${cold_start}  avg_cost=\$${avg_cost}"

  # Append to JSON results
  local tmp
  tmp=$(mktemp)
  jq --arg fn "$fn" \
     --arg label "$label" \
     --argjson mem "$mem" \
     --argjson avg "$avg_billed" \
     --argjson min "$min_billed" \
     --argjson max "$max_billed" \
     --arg cold "$cold_start" \
     --arg cost "$avg_cost" \
     '. += [{"function": $fn, "label": $label, "memory_mb": $mem,
             "avg_billed_ms": $avg, "min_billed_ms": $min, "max_billed_ms": $max,
             "cold_start": $cold, "avg_cost_usd": $cost}]' \
     "$RESULTS_FILE" > "$tmp"
  mv "$tmp" "$RESULTS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  Lambda Power Tuning Benchmark"
echo "  v1 (unoptimized): $V1_FUNCTION"
echo "  v2 (optimized):   $V2_FUNCTION"
echo "  Invocations per config: $INVOCATIONS"
echo "  Region: $REGION"
echo "============================================================"

for mem in "${MEMORY_SIZES[@]}"; do
  run_at_memory "$V1_FUNCTION" "v1_unoptimized" "$mem"
  run_at_memory "$V2_FUNCTION" "v2_optimized"   "$mem"
done

# Restore both functions to 128 MB baseline after benchmark
echo ""
echo "Restoring both functions to 128 MB..."
for fn in "$V1_FUNCTION" "$V2_FUNCTION"; do
  aws lambda update-function-configuration \
    --function-name "$fn" \
    --memory-size 128 \
    --region "$REGION" \
    --output json > /dev/null
done

# ─────────────────────────────────────────────────────────────────────────────
# Print summary table
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  RESULTS SUMMARY"
echo "============================================================"
printf "%-20s %-10s %-15s %-15s %-15s %-20s\n" \
  "Function" "Memory" "Avg Billed" "Min Billed" "Cold Start" "Avg Cost/invoke"
printf "%-20s %-10s %-15s %-15s %-15s %-20s\n" \
  "--------" "------" "----------" "----------" "----------" "---------------"

jq -r '.[] | [.label, (.memory_mb|tostring)+"MB", (.avg_billed_ms|tostring)+"ms",
              (.min_billed_ms|tostring)+"ms", .cold_start, "$"+.avg_cost_usd] | @tsv' \
  "$RESULTS_FILE" | \
while IFS=$'\t' read -r label mem avg min cold cost; do
  printf "%-20s %-10s %-15s %-15s %-15s %-20s\n" "$label" "$mem" "$avg" "$min" "$cold" "$cost"
done | tee "$SUMMARY_FILE"

echo ""
echo "Full results: $RESULTS_FILE"
echo "Summary:      $SUMMARY_FILE"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Find cost-optimal memory size for v2
# ─────────────────────────────────────────────────────────────────────────────
echo "Cost-optimal memory size for v2_optimized:"
jq -r '[.[] | select(.label == "v2_optimized")] | sort_by(.avg_cost_usd | tonumber) | .[0] |
  "  \(.memory_mb)MB — avg \(.avg_billed_ms)ms — \$\(.avg_cost_usd)/invoke"' "$RESULTS_FILE"

echo ""
echo "Done."
