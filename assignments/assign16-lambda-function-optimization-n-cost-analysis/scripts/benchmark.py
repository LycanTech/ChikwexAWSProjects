#!/usr/bin/env python3
"""
benchmark.py — Lambda Power Tuning (cross-platform)

Tests v1 (unoptimized) and v2 (optimized) at 128 / 256 / 512 / 1024 MB.
Captures billed duration and init duration from CloudWatch log tails.
Calculates cost per invocation and prints a comparison table.

Usage:
  python scripts/benchmark.py [--region us-east-1] [--invocations 5]

Prerequisites:
  - terraform apply completed
  - S3 seeded with seed_s3.py
  - pip install boto3
"""

import argparse
import base64
import json
from botocore.config import Config
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import boto3

# Lambda pricing (us-east-1)
PRICE_PER_GB_SEC  = 0.0000166667
PRICE_PER_REQUEST = 0.0000002

MEMORY_SIZES = [128, 256, 512, 1024]


def get_tf_output(key: str, tf_dir: Path) -> str:
    result = subprocess.run(
        ["terraform", "output", "-raw", key],
        cwd=tf_dir,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"ERROR: Could not read '{key}' from Terraform outputs.")
        print("       Run 'terraform apply' inside terraform/ first.")
        sys.exit(1)
    return result.stdout.strip()


def parse_log(log_b64: str) -> dict:
    """Decode CloudWatch log tail and extract duration metrics."""
    try:
        log = base64.b64decode(log_b64).decode("utf-8", errors="replace")
    except Exception:
        return {"billed_ms": 0, "init_ms": 0.0, "max_mem_mb": 0}

    billed = int(re.search(r"Billed Duration:\s+(\d+)", log).group(1)) \
        if re.search(r"Billed Duration:\s+(\d+)", log) else 0
    init_m = re.search(r"Init Duration:\s+([\d.]+)", log)
    init   = float(init_m.group(1)) if init_m else 0.0
    mem_m  = re.search(r"Max Memory Used:\s+(\d+)", log)
    maxmem = int(mem_m.group(1)) if mem_m else 0

    return {"billed_ms": billed, "init_ms": init, "max_mem_mb": maxmem}


def invoke(client, function_name: str) -> dict:
    resp = client.invoke(
        FunctionName=function_name,
        Payload=b"{}",
        LogType="Tail",
    )
    metrics = parse_log(resp.get("LogResult", ""))
    # Also pull result body
    body = json.loads(resp["Payload"].read())
    metrics["response"] = body
    return metrics


def cost(memory_mb: int, billed_ms: int) -> float:
    return (memory_mb / 1024) * (billed_ms / 1000) * PRICE_PER_GB_SEC + PRICE_PER_REQUEST


def update_memory(lambda_client, function_name: str, memory_mb: int) -> None:
    lambda_client.update_function_configuration(
        FunctionName=function_name,
        MemorySize=memory_mb,
    )
    # Wait for update to finish
    waiter = lambda_client.get_waiter("function_updated")
    waiter.wait(FunctionName=function_name)


def run_tier(lambda_client, function_name: str, label: str, memory_mb: int, invocations: int) -> dict:
    print(f"\n  [{label}] {memory_mb}MB — updating config...", flush=True)
    update_memory(lambda_client, function_name, memory_mb)

    billed_times = []
    cold_start_ms = None

    for i in range(1, invocations + 1):
        print(f"    invocation {i}/{invocations} ... ", end="", flush=True)
        metrics = invoke(lambda_client, function_name)

        billed = metrics["billed_ms"]
        init   = metrics["init_ms"]
        maxmem = metrics["max_mem_mb"]
        c      = cost(memory_mb, billed)

        if i == 1 and init > 0:
            cold_start_ms = init

        billed_times.append(billed)
        print(f"billed={billed}ms  init={init}ms  maxMem={maxmem}MB  cost=${c:.8f}")

    avg_billed = int(sum(billed_times) / len(billed_times))
    min_billed = min(billed_times)
    max_billed = max(billed_times)
    avg_cost   = cost(memory_mb, avg_billed)

    print(f"    ── avg={avg_billed}ms  min={min_billed}ms  max={max_billed}ms  "
          f"cold={cold_start_ms}ms  avg_cost=${avg_cost:.8f}")

    return {
        "label":         label,
        "function_name": function_name,
        "memory_mb":     memory_mb,
        "avg_billed_ms": avg_billed,
        "min_billed_ms": min_billed,
        "max_billed_ms": max_billed,
        "cold_start_ms": cold_start_ms,
        "avg_cost_usd":  round(avg_cost, 8),
    }


def print_table(results: list) -> str:
    header = f"{'Function':<22} {'Memory':>8} {'Avg Billed':>12} {'Min Billed':>12} {'Cold Start':>12} {'Cost/invoke':>14}"
    sep    = "-" * len(header)
    lines  = [sep, header, sep]
    for r in results:
        cold = f"{r['cold_start_ms']}ms" if r["cold_start_ms"] else "warm"
        line = (f"{r['label']:<22} {str(r['memory_mb'])+'MB':>8} "
                f"{str(r['avg_billed_ms'])+'ms':>12} {str(r['min_billed_ms'])+'ms':>12} "
                f"{cold:>12} ${r['avg_cost_usd']:>13.8f}")
        lines.append(line)
    lines.append(sep)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Lambda power tuning benchmark")
    parser.add_argument("--region",      default="us-east-1")
    parser.add_argument("--invocations", type=int, default=5)
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    tf_dir     = script_dir.parent / "terraform"
    results_dir = script_dir.parent / "results"
    results_dir.mkdir(exist_ok=True)

    v1_name = get_tf_output("lambda_v1_name", tf_dir)
    v2_name = get_tf_output("lambda_v2_name", tf_dir)

    # v1 at 128MB takes ~85s — default boto3 read timeout is 60s, must raise it
    boto_config = Config(
        read_timeout=310,
        connect_timeout=10,
        retries={"max_attempts": 0},
    )
    lambda_client = boto3.client("lambda", region_name=args.region, config=boto_config)

    print("=" * 60)
    print("  Lambda Power Tuning Benchmark")
    print(f"  v1 (unoptimized): {v1_name}")
    print(f"  v2 (optimized):   {v2_name}")
    print(f"  Invocations per config: {args.invocations}")
    print(f"  Memory tiers: {MEMORY_SIZES}")
    print("=" * 60)

    all_results = []

    for mem in MEMORY_SIZES:
        all_results.append(run_tier(lambda_client, v1_name, "v1_unoptimized", mem, args.invocations))
        all_results.append(run_tier(lambda_client, v2_name, "v2_optimized",   mem, args.invocations))

    # Restore both to 128 MB
    print("\nRestoring both functions to 128MB...")
    for fn in [v1_name, v2_name]:
        update_memory(lambda_client, fn, 128)

    # Write JSON
    results_file = results_dir / "benchmark_results.json"
    results_file.write_text(json.dumps(all_results, indent=2))

    # Print summary table
    print("\n" + "=" * 60)
    print("  RESULTS SUMMARY")
    print("=" * 60)
    table = print_table(all_results)
    print(table)

    summary_file = results_dir / "summary.txt"
    summary_file.write_text(table)

    # Cost-optimal for v2
    v2_results = [r for r in all_results if r["label"] == "v2_optimized"]
    optimal    = min(v2_results, key=lambda r: r["avg_cost_usd"])
    print(f"\nCost-optimal config for v2_optimized: {optimal['memory_mb']}MB "
          f"— avg {optimal['avg_billed_ms']}ms — ${optimal['avg_cost_usd']:.8f}/invoke")

    print(f"\nFull results: {results_file}")
    print(f"Summary:      {summary_file}")


if __name__ == "__main__":
    main()
