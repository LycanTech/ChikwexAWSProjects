#!/usr/bin/env python3
"""
replay.py — Replay messages from the DLQ back to the main queue.

Reads all messages currently visible in the DLQ and re-sends them
to the target queue for reprocessing. Deletes each message from the
DLQ only after it is successfully re-queued.

Usage:
  python scripts/replay.py --dlq-url <url> --target-url <url> [--region us-east-1] [--max 0]

Options:
  --max   Maximum messages to replay (0 = all, default: 0)
"""

import argparse
import json
import sys
import time

import boto3


def drain(sqs, queue_url: str, max_messages: int) -> list[dict]:
    """Pull all visible messages from a queue using long polling."""
    messages = []
    empty_polls = 0

    print(f"Draining DLQ: {queue_url}")
    while True:
        resp = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=5,
            AttributeNames=["All"],
            MessageAttributeNames=["All"],
        )
        batch = resp.get("Messages", [])
        if not batch:
            empty_polls += 1
            if empty_polls >= 2:
                break
            continue

        empty_polls = 0
        messages.extend(batch)
        print(f"  fetched {len(messages)} so far...")

        if max_messages and len(messages) >= max_messages:
            messages = messages[:max_messages]
            break

    return messages


def replay(sqs, messages: list[dict], target_url: str, dlq_url: str) -> tuple[int, int]:
    replayed = 0
    failed   = 0

    for msg in messages:
        body       = msg["Body"]
        receipt    = msg["ReceiptHandle"]
        message_id = msg["MessageId"]

        try:
            sqs.send_message(QueueUrl=target_url, MessageBody=body)
            sqs.delete_message(QueueUrl=dlq_url, ReceiptHandle=receipt)
            replayed += 1
            print(f"  OK replayed {message_id}")
        except Exception as exc:
            failed += 1
            print(f"  ERR failed  {message_id}: {exc}", file=sys.stderr)

    return replayed, failed


def get_queue_depth(sqs, queue_url: str) -> int:
    resp = sqs.get_queue_attributes(
        QueueUrl=queue_url,
        AttributeNames=["ApproximateNumberOfMessages"],
    )
    return int(resp["Attributes"].get("ApproximateNumberOfMessages", 0))


def main():
    parser = argparse.ArgumentParser(description="Replay DLQ messages to main queue")
    parser.add_argument("--dlq-url",    required=True, help="Source DLQ URL")
    parser.add_argument("--target-url", required=True, help="Target queue URL (main queue)")
    parser.add_argument("--max",        type=int, default=0, help="Max messages to replay (0=all)")
    parser.add_argument("--region",     default="us-east-1")
    args = parser.parse_args()

    sqs = boto3.client("sqs", region_name=args.region)

    # Show queue depths before replay
    dlq_depth    = get_queue_depth(sqs, args.dlq_url)
    target_depth = get_queue_depth(sqs, args.target_url)
    print(f"Before replay - DLQ depth: {dlq_depth}  main queue depth: {target_depth}")

    if dlq_depth == 0:
        print("DLQ is empty — nothing to replay.")
        return

    messages = drain(sqs, args.dlq_url, args.max)
    print(f"Fetched {len(messages)} messages from DLQ.")

    start = time.time()
    replayed, failed = replay(sqs, messages, args.target_url, args.dlq_url)
    elapsed = time.time() - start

    # Show queue depths after replay
    time.sleep(2)
    dlq_depth_after    = get_queue_depth(sqs, args.dlq_url)
    target_depth_after = get_queue_depth(sqs, args.target_url)

    print(f"\nReplay complete in {elapsed:.2f}s")
    print(f"  Replayed: {replayed}  Failed: {failed}")
    print(f"After replay - DLQ depth: {dlq_depth_after}  main queue depth: {target_depth_after}")

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
