"""
DLQ Monitor Lambda

Triggers when messages arrive in the Dead Letter Queue (failed-messages).
Analyzes failure patterns, logs a detailed report to CloudWatch,
and publishes an SNS alert with a summary.
"""

import json
import logging
import os
from collections import Counter
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client("sns")
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
QUEUE_NAME    = os.environ.get("QUEUE_NAME", "failed-messages")


def parse_body(raw: str) -> dict:
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return {"raw": str(raw)}


def handler(event, context):
    records = event.get("Records", [])
    if not records:
        return

    now = datetime.now(timezone.utc).isoformat()
    message_ids   = []
    categories    = Counter()
    sample_bodies = []

    for record in records:
        message_id    = record["messageId"]
        body          = record["body"]
        receive_count = int(record["attributes"].get("ApproximateReceiveCount", 1))
        sent_ts       = record["attributes"].get("SentTimestamp", "unknown")

        data = parse_body(body)
        category = data.get("category", "unknown")
        categories[category] += 1
        message_ids.append(message_id)

        if len(sample_bodies) < 5:
            sample_bodies.append({
                "messageId":    message_id,
                "receiveCount": receive_count,
                "sentAt":       sent_ts,
                "category":     category,
                "body":         body[:200],
            })

        logger.info(
            "DLQ_ARRIVAL messageId=%s receiveCount=%d category=%s sentAt=%s",
            message_id, receive_count, category, sent_ts,
        )

    # Failure pattern summary
    logger.info(
        "DLQ_SUMMARY count=%d categories=%s messageIds=%s",
        len(message_ids),
        dict(categories),
        message_ids,
    )

    # SNS alert
    alert = {
        "alert":      "DLQ Messages Detected",
        "queue":      QUEUE_NAME,
        "timestamp":  now,
        "count":      len(message_ids),
        "categories": dict(categories),
        "sample_messages": sample_bodies,
    }

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[ALERT] {len(message_ids)} message(s) landed in DLQ: {QUEUE_NAME}",
        Message=json.dumps(alert, indent=2),
    )

    logger.info("SNS alert published to %s", SNS_TOPIC_ARN)

    return {
        "dlq_messages_processed": len(message_ids),
        "categories": dict(categories),
    }
