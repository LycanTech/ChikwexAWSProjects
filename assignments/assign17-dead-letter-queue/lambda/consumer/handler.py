"""
SQS Consumer Lambda

Processes messages from main-queue one at a time.
Randomly fails 20% of messages to simulate real-world error rates.
SQS will retry failed messages up to maxReceiveCount (3) times before
routing them to the Dead Letter Queue.
"""

import json
import logging
import os
import random

logger = logging.getLogger()
logger.setLevel(logging.INFO)

FAIL_RATE = float(os.environ.get("FAIL_RATE", "0.20"))


def handler(event, context):
    results = {"success": [], "failed": []}

    for record in event["Records"]:
        message_id    = record["messageId"]
        body          = record["body"]
        receive_count = int(record["attributes"].get("ApproximateReceiveCount", 1))

        logger.info(
            "ATTEMPT messageId=%s attempt=%d body=%s",
            message_id, receive_count, body[:120],
        )

        # Seed the RNG with the message ID so the same message always
        # hits the same fate on every retry attempt.
        rng = random.Random(message_id)
        should_fail = rng.random() < FAIL_RATE

        if should_fail:
            logger.warning(
                "FAIL messageId=%s attempt=%d — simulated processing error",
                message_id, receive_count,
            )
            results["failed"].append(message_id)
            # Raising an exception causes SQS to make the message visible again.
            # After maxReceiveCount retries it moves to the DLQ.
            raise Exception(
                f"Simulated failure for message {message_id} (attempt {receive_count})"
            )

        # Parse and process
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            data = {"raw": body}

        logger.info(
            "SUCCESS messageId=%s attempt=%d data=%s",
            message_id, receive_count, str(data)[:120],
        )
        results["success"].append(message_id)

    return results
