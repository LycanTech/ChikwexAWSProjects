#!/usr/bin/env python3
"""
Seed S3 with 1000 JSON objects for the Lambda optimization benchmark.

Each object is ~200-300 bytes of realistic JSON:
  {
    "id":        "item-000001",
    "value":     42.57,
    "category":  "electronics",
    "timestamp": "2026-05-05T10:00:00Z",
    "tags":      ["sale", "featured"],
    "metadata":  { "weight_kg": 0.85, "warehouse": "us-east-1a" }
  }

Usage:
  python scripts/seed_s3.py --bucket <bucket> [--prefix data/] [--count 1000] [--region us-east-1]
"""

import argparse
import json
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

import boto3

CATEGORIES = ["electronics", "clothing", "furniture", "books", "sports", "toys", "food", "tools"]
TAG_POOL   = ["sale", "featured", "new", "clearance", "bestseller", "limited", "refurbished"]
WAREHOUSES = ["us-east-1a", "us-east-1b", "us-east-1c"]


def make_item(index: int) -> dict:
    rng = random.Random(index)
    return {
        "id":        f"item-{index:06d}",
        "value":     round(rng.uniform(0.99, 999.99), 2),
        "category":  rng.choice(CATEGORIES),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tags":      rng.sample(TAG_POOL, k=rng.randint(1, 3)),
        "metadata": {
            "weight_kg": round(rng.uniform(0.1, 25.0), 2),
            "warehouse": rng.choice(WAREHOUSES),
            "stock":     rng.randint(0, 500),
        },
    }


def upload_one(s3_client, bucket: str, prefix: str, index: int) -> str:
    item = make_item(index)
    key  = f"{prefix}item-{index:06d}.json"
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(item).encode(),
        ContentType="application/json",
    )
    return key


def main():
    parser = argparse.ArgumentParser(description="Seed S3 with JSON objects")
    parser.add_argument("--bucket",  required=True, help="Target S3 bucket name")
    parser.add_argument("--prefix",  default="data/", help="Key prefix (default: data/)")
    parser.add_argument("--count",   type=int, default=1000, help="Number of objects (default: 1000)")
    parser.add_argument("--workers", type=int, default=50,   help="Parallel upload workers (default: 50)")
    parser.add_argument("--region",  default="us-east-1",    help="AWS region (default: us-east-1)")
    args = parser.parse_args()

    s3 = boto3.client("s3", region_name=args.region)

    print(f"Uploading {args.count} objects to s3://{args.bucket}/{args.prefix} ...")
    start = time.time()

    uploaded = 0
    failed   = 0

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {
            pool.submit(upload_one, s3, args.bucket, args.prefix, i): i
            for i in range(1, args.count + 1)
        }
        for future in as_completed(futures):
            try:
                future.result()
                uploaded += 1
                if uploaded % 100 == 0:
                    elapsed = time.time() - start
                    print(f"  {uploaded}/{args.count} uploaded ({elapsed:.1f}s elapsed)")
            except Exception as exc:
                failed += 1
                print(f"  ERROR on item {futures[future]}: {exc}", file=sys.stderr)

    elapsed = time.time() - start
    print(f"\nDone. {uploaded} uploaded, {failed} failed in {elapsed:.2f}s")
    print(f"Average: {elapsed / max(uploaded, 1) * 1000:.1f} ms/object")

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
