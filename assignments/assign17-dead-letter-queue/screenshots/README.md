# Assignment 17 — Screenshots Index

All CLI captures taken on 2026-05-06.

## Infrastructure evidence (taken after `terraform apply`)

| File | Resource | What it shows |
| --- | --- | --- |
| `01-sqs-main-queue.json` | `chikwex-assign17-main-queue` | Queue attributes: visibility timeout 30s, redrive policy → DLQ (maxReceiveCount=3) |
| `02-sqs-dlq.json` | `chikwex-assign17-failed-messages` | DLQ attributes: 14-day retention, redrive allow policy |
| `03-sqs-fifo-main-queue.json` | `chikwex-assign17-main-queue.fifo` | FIFO queue with content-based deduplication |
| `04-sqs-fifo-dlq.json` | `chikwex-assign17-failed-messages.fifo` | FIFO DLQ |
| `05-lambda-consumer.json` | `chikwex-assign17-consumer` | Consumer Lambda config (FAIL_RATE=0.20, timeout=30s) |
| `06-lambda-dlq-monitor.json` | `chikwex-assign17-dlq-monitor` | DLQ monitor Lambda config (SNS_TOPIC_ARN env var) |
| `07-esm-consumer.json` | Event source mapping | Consumer ← main-queue (batch=1, enabled) |
| `08-esm-dlq-monitor.json` | Event source mapping | dlq-monitor ← DLQ (batch=10, enabled) |
| `09-sns-topic.json` | `chikwex-assign17-dlq-alerts` | SNS topic attributes |
| `10-sns-subscription.json` | Email subscription | `chikwe.azinge@techconsulting.tech` (pending confirmation) |
| `11-cloudwatch-log-groups.json` | Log groups | Both Lambda log groups with 7-day retention |

## Live test evidence (captured after sending 100 messages)

| File | What it shows |
| --- | --- |
| `12-consumer-lambda-logs.json` | 791 CloudWatch events: ATTEMPT/SUCCESS/FAIL lines (20% fail rate confirmed, messages retried ×3 before DLQ) |
| `13-dlq-monitor-lambda-logs.json` | 140 CloudWatch events: 22 DLQ_ARRIVAL + 22 SNS alerts published |
| `14-replay-output.txt` | replay.py output showing DLQ drained (10→0) and messages re-queued to main queue |

## Test summary

| Metric | Observed |
| --- | --- |
| Messages sent | 100 |
| Successful on first attempt | ~80 |
| Failed all 3 attempts → DLQ | 22 |
| DLQ_ARRIVAL events logged | 22 |
| SNS alerts published | 22 |
| Messages replayed from DLQ | 10 (per run) |

## Console screenshots to take manually

- SQS console → all 4 queues listed
- `chikwex-assign17-main-queue` → Dead-letter queue tab (shows DLQ ARN + maxReceiveCount=3)
- Lambda `chikwex-assign17-consumer` → Configuration → Triggers (shows SQS trigger)
- Lambda `chikwex-assign17-dlq-monitor` → Configuration → Triggers (shows DLQ trigger)
- SNS topic → Subscriptions tab (shows email endpoint)
- CloudWatch → consumer logs showing ATTEMPT/SUCCESS/FAIL lines
- CloudWatch → dlq-monitor logs showing DLQ_ARRIVAL + DLQ_SUMMARY
