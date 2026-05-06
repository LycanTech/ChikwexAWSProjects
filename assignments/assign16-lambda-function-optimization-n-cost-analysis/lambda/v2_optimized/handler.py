"""
Lambda v2 — Optimized

Optimizations applied vs v1:
  1. Connection pooling  — boto3 clients created at module level, reused across warm invocations
  2. Async/concurrent reads — ThreadPoolExecutor fetches S3 objects in parallel
  3. Batch DynamoDB writes — batch_write_item sends 25 items per API call instead of 1
"""

import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Connection pooling: clients at module level ───────────────────────────────
# These survive across warm invocations, eliminating repeated TLS handshake cost.
s3 = boto3.client("s3")
dynamodb = boto3.client("dynamodb")

BUCKET_NAME = os.environ.get("BUCKET_NAME", "")
TABLE_NAME = os.environ.get("TABLE_NAME", "")
OBJECT_PREFIX = os.environ.get("OBJECT_PREFIX", "data/")

MAX_WORKERS = 50       # concurrent S3 fetches
DYNAMO_BATCH = 25      # DynamoDB batch_write_item limit


def _fetch(key: str) -> dict:
    resp = s3.get_object(Bucket=BUCKET_NAME, Key=key)
    return json.loads(resp["Body"].read())


def _batch_write(items: list, processed_at: str) -> None:
    for i in range(0, len(items), DYNAMO_BATCH):
        batch = items[i : i + DYNAMO_BATCH]
        dynamodb.batch_write_item(
            RequestItems={
                TABLE_NAME: [
                    {
                        "PutRequest": {
                            "Item": {
                                "id":           {"S": item["id"]},
                                "value":        {"N": str(item["value"])},
                                "category":     {"S": item["category"]},
                                "processed_at": {"S": processed_at},
                            }
                        }
                    }
                    for item in batch
                ]
            }
        )


def handler(event, context):
    start = time.time()

    # ── List objects ──────────────────────────────────────────────────────────
    list_resp = s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=OBJECT_PREFIX, MaxKeys=1000)
    keys = [obj["Key"] for obj in list_resp.get("Contents", [])]
    logger.info("Found %d objects in s3://%s/%s", len(keys), BUCKET_NAME, OBJECT_PREFIX)

    # ── Concurrent reads ──────────────────────────────────────────────────────
    items = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(_fetch, key): key for key in keys}
        for future in as_completed(futures):
            items.append(future.result())

    read_done = time.time()
    logger.info(
        "Concurrent read complete: %.3fs for %d objects (workers=%d)",
        read_done - start,
        len(items),
        MAX_WORKERS,
    )

    # ── Batch DynamoDB writes ─────────────────────────────────────────────────
    processed_at = str(time.time())
    _batch_write(items, processed_at)

    total = time.time() - start
    batches = -(-len(items) // DYNAMO_BATCH)  # ceiling division
    logger.info(
        "RESULT version=v2_optimized items=%d batches=%d total_seconds=%.3f memory_mb=%s",
        len(items),
        batches,
        total,
        context.memory_limit_in_mb,
    )

    return {
        "version": "v2_optimized",
        "items_processed": len(items),
        "dynamo_batches": batches,
        "total_seconds": round(total, 3),
        "memory_mb": context.memory_limit_in_mb,
    }
