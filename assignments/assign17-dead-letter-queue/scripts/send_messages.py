#!/usr/bin/env python3
"""
send_messages.py — Send N test messages to the SQS main queue.

Usage:
  python scripts/send_messages.py --queue-url <url> [--count 100] [--region us-east-1]

Each message contains realistic JSON:
  { "id": "msg-000001", "category": "orders", "payload": "...", "timestamp": "..." }
"""

import argparse
import json
import sys
import time
import uuid
from datetime import datetime, timezone

import boto3

CATEGORIES = ["orders", "payments", "inventory", "shipping", "notifications", "analytics"]


def make_message(index: int) -> dict:
    return {
        "id":        f"msg-{index:06d}",
        "category":  CATEGORIES[index % len(CATEGORIES)],
        "payload":   f"test-payload-{index}",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "sequence":  index,
    }


def send_batch(sqs, queue_url: str, messages: list) -> tuple[int, int]:
    """Send up to 10 messages in one SendMessageBatch call. Returns (success, failed)."""
    entries = [
        {
            "Id":          str(i),
            "MessageBody": json.dumps(msg),
        }
        for i, msg in enumerate(messages)
    ]
    resp    = sqs.send_message_batch(QueueUrl=queue_url, Entries=entries)
    success = len(resp.get("Successful", []))
    failed  = len(resp.get("Failed", []))
    return success, failed


def main():
    parser = argparse.ArgumentParser(description="Send test messages to SQS")
    parser.add_argument("--queue-url", required=True, help="SQS queue URL")
    parser.add_argument("--count",     type=int, default=100, help="Number of messages (default: 100)")
    parser.add_argument("--region",    default="us-east-1")
    args = parser.parse_args()

    sqs = boto3.client("sqs", region_name=args.region)

    print(f"Sending {args.count} messages to {args.queue_url}")
    start      = time.time()
    total_sent = 0
    total_fail = 0
    batch_size = 10

    messages = [make_message(i) for i in range(1, args.count + 1)]

    for i in range(0, len(messages), batch_size):
        batch          = messages[i : i + batch_size]
        success, failed = send_batch(sqs, args.queue_url, batch)
        total_sent += success
        total_fail += failed
        print(f"  batch {i // batch_size + 1}: {success} sent, {failed} failed")

    elapsed = time.time() - start
    print(f"\nDone. {total_sent} sent, {total_fail} failed in {elapsed:.2f}s")
    print(f"Expect ~{int(args.count * 0.20)} messages to reach the DLQ after 3 retry attempts.")

    if total_fail:
        sys.exit(1)


if __name__ == "__main__":
    main()
