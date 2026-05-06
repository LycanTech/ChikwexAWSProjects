# Assignment 16 — Lambda Function Optimization & Cost Analysis

## Overview

This assignment benchmarks two versions of a Lambda function that reads 1000 JSON objects from S3, processes them, and writes results to DynamoDB. The unoptimized baseline (v1) uses sequential reads and individual writes. The optimized version (v2) applies connection pooling, concurrent S3 reads via `ThreadPoolExecutor`, and DynamoDB batch writes. Both are tested at 128 / 256 / 512 / 1024 MB with X-Ray tracing enabled to identify the cost-optimal memory configuration.

---

## Architecture

```text
                  ┌─────────────────────────────────────────────┐
                  │                   Lambda                     │
                  │                                             │
                  │  v1 (unoptimized, 128MB start)             │
                  │    Sequential S3 get_object × 1000         │
                  │    Individual DynamoDB put_item × 1000      │
                  │                                             │
                  │  v2 (optimized, 128–1024MB)                │
                  │    Concurrent S3 reads (50 workers)         │
                  │    DynamoDB batch_write_item (25/call)      │
                  │    Module-level boto3 client reuse          │
                  └────────┬──────────────────┬────────────────┘
                           │                  │
                  ┌────────▼──────┐  ┌────────▼──────┐
                  │  S3 Bucket    │  │   DynamoDB     │
                  │  1000 JSON    │  │   results      │
                  │  objects      │  │   table        │
                  └───────────────┘  └───────────────┘
                           │
                  ┌────────▼──────┐
                  │   X-Ray       │
                  │  (tracing)    │
                  └───────────────┘
```

---

## What's Optimized

| Technique | v1 (unoptimized) | v2 (optimized) |
| --- | --- | --- |
| boto3 client lifecycle | Created inside handler — no reuse | Module-level — reused across warm invocations |
| S3 reads | Sequential (1 at a time) | Concurrent via `ThreadPoolExecutor` (50 workers) |
| DynamoDB writes | `put_item` × 1000 (1 API call/item) | `batch_write_item` (25 items/call = 40 API calls) |
| API call reduction | 1000 S3 + 1000 DynamoDB = 2000 calls | 1000 S3 + 40 DynamoDB = 1040 calls |

---

## Project Structure

```text
├── README.md
├── lambda/
│   ├── v1_unoptimized/
│   │   └── handler.py        # Sequential reads, individual DynamoDB puts
│   └── v2_optimized/
│       └── handler.py        # Concurrent reads, batch DynamoDB writes, connection pooling
├── terraform/
│   ├── main.tf               # S3, DynamoDB, IAM role, both Lambda functions
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars
└── scripts/
    ├── seed_s3.py            # Upload 1000 JSON objects to S3
    ├── benchmark.py          # Power-tune both functions at 4 memory sizes (cross-platform)
    └── benchmark.sh          # Bash equivalent (Linux/macOS only)
```

---

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured (`us-east-1`)
- Python 3.9+ with `boto3` (`pip install boto3`)

---

## Deployment

### Step 1 — Deploy infrastructure

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

Note the outputs:

```text
s3_bucket      = "chikwex-assign16-data-866934333672"
dynamodb_table = "chikwex-assign16-results"
lambda_v1_name = "chikwex-assign16-v1-unoptimized"
lambda_v2_name = "chikwex-assign16-v2-optimized"
```

### Step 2 — Seed S3 with 1000 objects

```powershell
python scripts/seed_s3.py --bucket chikwex-assign16-data-866934333672 --count 1000
```

This uploads 1000 JSON objects to `s3://<bucket>/data/item-000001.json` through `item-001000.json` using 50 parallel workers (~5–10 seconds).

### Step 3 — Run the benchmark

```powershell
python scripts/benchmark.py
```

The script:

1. Updates each function's memory size (128 → 256 → 512 → 1024 MB)
2. Invokes each 5 times per memory tier, capturing billed duration from CloudWatch log tails
3. Calculates cost per invocation (`(memory_gb × billed_sec) × $0.0000166667 + $0.0000002`)
4. Prints a comparison table and identifies the cost-optimal memory size for v2
5. Writes `results/benchmark_results.json` and `results/summary.txt`
6. Restores both functions to 128 MB

Optional flags:

```powershell
python scripts/benchmark.py --invocations 3 --region us-east-1
```

---

## Manual Invocation

Test a single invocation of either function at any time:

```powershell
# v1 — unoptimized
aws lambda invoke `
  --function-name chikwex-assign16-v1-unoptimized `
  --payload '{}' `
  --log-type Tail `
  --cli-binary-format raw-in-base64-out `
  --region us-east-1 `
  response.json

# v2 — optimized
aws lambda invoke `
  --function-name chikwex-assign16-v2-optimized `
  --payload '{}' `
  --log-type Tail `
  --cli-binary-format raw-in-base64-out `
  --region us-east-1 `
  response.json
```

---

## X-Ray Tracing

Both functions have `tracing_config { mode = "Active" }`. After invocation, view traces in the AWS Console:

- [X-Ray Service Map](https://us-east-1.console.aws.amazon.com/xray/home?region=us-east-1#/service-map)
- [X-Ray Traces](https://us-east-1.console.aws.amazon.com/xray/home?region=us-east-1#/traces)

X-Ray breaks down time spent in each subsegment (S3 reads, DynamoDB writes), making the performance difference between v1 and v2 visually clear.

---

## Cold Start vs Warm Start

The benchmark script records the `Init Duration` from CloudWatch log tails on the first invocation (cold start), and subsequent invocations measure warm execution time. Key targets:

| Metric | Target | Notes |
| --- | --- | --- |
| Cold start | < 3 seconds | Python 3.12 Lambda, no heavy dependencies |
| Warm execution (v2) | < 1 second | Achievable at 512MB+ with concurrent reads |

---

## Expected Results

Results will vary — the pattern typically observed:

| Version | Memory | Avg Billed | Approx Cost/invoke |
| --- | --- | --- | --- |
| v1_unoptimized | 128 MB | ~90–120 s | ~$0.0002 |
| v1_unoptimized | 512 MB | ~30–50 s | ~$0.0003 |
| v2_optimized | 128 MB | ~15–25 s | ~$0.000035 |
| v2_optimized | 256 MB | ~8–12 s | ~$0.000038 |
| v2_optimized | 512 MB | ~5–8 s | ~$0.000045 |
| v2_optimized | 1024 MB | ~4–6 s | ~$0.000067 |

**Cost-optimal**: v2 at **128–256 MB** typically wins on cost because the concurrent reads and batch writes compress wall time so aggressively that doubling memory costs more than it saves.

---

## AWS Console Links

| Resource | Link |
| --- | --- |
| Lambda functions | [chikwex-assign16-*](https://us-east-1.console.aws.amazon.com/lambda/home?region=us-east-1#/functions?fo=and&k0=functionName&o0=%3A&v0=chikwex-assign16) |
| S3 bucket | [chikwex-assign16-data-866934333672](https://s3.console.aws.amazon.com/s3/buckets/chikwex-assign16-data-866934333672?region=us-east-1) |
| DynamoDB table | [chikwex-assign16-results](https://us-east-1.console.aws.amazon.com/dynamodb/home?region=us-east-1#table?name=chikwex-assign16-results) |
| X-Ray Service Map | [Service Map](https://us-east-1.console.aws.amazon.com/xray/home?region=us-east-1#/service-map) |
| CloudWatch Logs (v1) | [v1 log group](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/%2Faws%2Flambda%2Fchikwex-assign16-v1-unoptimized) |
| CloudWatch Logs (v2) | [v2 log group](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/%2Faws%2Flambda%2Fchikwex-assign16-v2-optimized) |

---

## Cleanup

```bash
terraform destroy -auto-approve
```

This removes both Lambda functions, S3 bucket (including all 1000 objects), DynamoDB table, IAM role, and CloudWatch log groups.
