"""
Lambda v1 — Unoptimized baseline

Intentionally unoptimized to demonstrate the performance penalty of:
  - Creating boto3 clients inside the handler (no connection reuse across warm invocations)
  - Sequential S3 object reads (one get_object call at a time)
  - Individual DynamoDB put_item calls (one write per item, no batching)
"""

import json
import logging
import os
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    start = time.time()

    # Clients created inside handler — no reuse on warm starts
    s3 = boto3.client("s3")
    dynamodb = boto3.client("dynamodb")

    bucket = os.environ["BUCKET_NAME"]
    table = os.environ["TABLE_NAME"]
    prefix = os.environ.get("OBJECT_PREFIX", "data/")

    # ── List objects ──────────────────────────────────────────────────────────
    list_resp = s3.list_objects_v2(Bucket=bucket, Prefix=prefix, MaxKeys=1000)
    keys = [obj["Key"] for obj in list_resp.get("Contents", [])]
    logger.info("Found %d objects in s3://%s/%s", len(keys), bucket, prefix)

    # ── Sequential reads ──────────────────────────────────────────────────────
    items = []
    for key in keys:
        resp = s3.get_object(Bucket=bucket, Key=key)
        data = json.loads(resp["Body"].read())
        items.append(data)

    read_done = time.time()
    logger.info("Sequential read complete: %.3fs for %d objects", read_done - start, len(items))

    # ── Individual DynamoDB writes ────────────────────────────────────────────
    processed_at = str(time.time())
    for item in items:
        dynamodb.put_item(
            TableName=table,
            Item={
                "id":           {"S": item["id"]},
                "value":        {"N": str(item["value"])},
                "category":     {"S": item["category"]},
                "processed_at": {"S": processed_at},
            },
        )

    total = time.time() - start
    logger.info(
        "RESULT version=v1_unoptimized items=%d total_seconds=%.3f memory_mb=%s",
        len(items),
        total,
        context.memory_limit_in_mb,
    )

    return {
        "version": "v1_unoptimized",
        "items_processed": len(items),
        "total_seconds": round(total, 3),
        "memory_mb": context.memory_limit_in_mb,
    }
