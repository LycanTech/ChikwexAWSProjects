# Assignment 12 – CloudWatch Logs Insights and Alarms

Advanced log analysis and alerting system using AWS Lambda, CloudWatch Logs, Logs Insights, Metric Filters, and Alarms.

---

## Architecture

```
Lambda Function (100 invocations)
    │
    └─► CloudWatch Log Group: /aws/lambda/chikwex-cw-demo
            │
            ├─► Logs Insights Queries
            │       ├── Error rate per minute
            │       ├── Average response time
            │       ├── Top 5 error codes
            │       └── Failed requests by user_id
            │
            └─► Metric Filters  →  Custom Metrics (chikwex/AppMetrics)
                    ├── HTTP500ErrorCount
                    ├── SlowRequestCount
                    └── ResponseTime
                            │
                            └─► CloudWatch Alarms
                                    ├── chikwex-high-error-rate    → SNS → Email
                                    └── chikwex-high-response-time → SNS → Email
```

---

## AWS Resources

| Resource | Name |
|---|---|
| Lambda Function | `chikwex-cw-demo` |
| IAM Role | `chikwex-cw-lambda-role` |
| Log Group | `/aws/lambda/chikwex-cw-demo` |
| SNS Topic | `chikwex-cw-alarms` |
| CW Namespace | `chikwex/AppMetrics` |
| Alarm – Errors | `chikwex-high-error-rate` |
| Alarm – Latency | `chikwex-high-response-time` |

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- Python 3.8+ with boto3 installed (`pip install boto3`)
- IAM permissions for: Lambda, CloudWatch, CloudWatch Logs, SNS, IAM

---

## File Structure

```
Assign12CloudWatchLogsInsightsandAlarms/
├── CloudWatchAssignment     # Original assignment spec
├── lambda_function.py       # Lambda code – generates logs
├── setup.py                 # Provisions all AWS resources
├── invoke.py                # Fires Lambda 100 times
├── insights_queries.md      # 4 copy-paste Logs Insights queries
├── teardown.py              # Deletes all resources
└── README.md                # This file
```

---

## Step-by-Step Implementation

### Step 1 – Understand the Lambda Function

**File:** `lambda_function.py`

The Lambda simulates an API endpoint that generates structured JSON logs. Every invocation randomly produces one of three outcomes:

| Outcome | Probability | Log Level | Response Time |
|---|---|---|---|
| Success | 65% | `INFO` | 50 – 499 ms |
| Slow | 20% | `WARN` | 500 – 2000 ms |
| Error | 15% | `ERROR` | 100 – 800 ms |

Each log line is a JSON object, for example:
```json
{"level": "ERROR", "user_id": "user_003", "operation": "POST /api/orders",
 "response_time": 312, "status": "error", "error_code": 500,
 "message": "Request failed with HTTP 500"}
```

CloudWatch captures every `logger.info/warning/error` call automatically.

---

### Step 2 – Run setup.py

This single script creates every AWS resource in the correct order:
1. IAM execution role for Lambda
2. Lambda function (packages and uploads `lambda_function.py`)
3. SNS topic + email subscription
4. CloudWatch log group (must exist before metric filters)
5. Three metric filters
6. Two CloudWatch alarms

```bash
python setup.py --email your@email.com
```

Expected output:
```
=== Assignment 12 Setup ===

[OK] Created IAM role: arn:aws:iam::866934333672:role/chikwex-cw-lambda-role
[OK] Created Lambda: arn:aws:lambda:us-east-1:866934333672:function:chikwex-cw-demo
[OK] SNS topic: arn:aws:sns:us-east-1:866934333672:chikwex-cw-alarms
[!!] Subscription confirmation email sent to your@email.com ...
[OK] Created log group: /aws/lambda/chikwex-cw-demo
[OK] Metric filter 'chikwex-500-errors': Count of HTTP 500 errors
[OK] Metric filter 'chikwex-slow-requests': Count of slow requests (>500ms)
[OK] Metric filter 'chikwex-response-time': Response time in milliseconds
[OK] Alarm: chikwex-high-error-rate  (HTTP500Count > 3 in 5 min)
[OK] Alarm: chikwex-high-response-time  (AvgResponseTime > 1000ms in 5 min)

=== Setup Complete ===
```

> **IMPORTANT:** Before moving to the next step, open your email and click the SNS confirmation link. Without this, alarms will fire but no email will be delivered.

---

### Step 3 – Confirm SNS Email Subscription

1. Open your inbox for the email address you provided
2. Find the email from **AWS Notifications** with subject `AWS Notification - Subscription Confirmation`
3. Click **Confirm subscription**
4. Verify in the console: [SNS Subscriptions](https://us-east-1.console.aws.amazon.com/sns/v3/home?region=us-east-1#/subscriptions) — status should be `Confirmed` (not `PendingConfirmation`)

---

### Step 4 – Invoke the Lambda 100 Times

```bash
python invoke.py
```

This fires the Lambda 100 times with a 300ms delay between calls, spreading logs across time so Insights queries return per-minute data rather than a single burst.

Expected output (abbreviated):
```
Invoking chikwex-cw-demo × 100 ...

  [ 10/100] running totals: {200: 7, 500: 2, 503: 1}
  [ 20/100] running totals: {200: 13, 500: 3, 503: 2, 404: 1, 429: 1}
  ...
  [100/100] running totals: {200: 65, 500: 8, 503: 4, 404: 3, 401: 2, 429: 3}

=== Final Results ===
  Total invocations : 100
  Successful (2xx)  : 85  (85.0%)
  Errors            : 15  (15.0%)
```

Wait ~2 minutes for logs to fully propagate into CloudWatch before running queries.

---

### Step 5 – Verify Logs in CloudWatch

1. Open [Log Group](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Fchikwex-cw-demo)
2. You should see one or more **Log Streams** (one per Lambda container)
3. Click a stream and confirm entries look like structured JSON

---

### Step 6 – Run Logs Insights Queries

1. Open [Logs Insights](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:logs-insights)
2. Under **Select log group(s)** choose `/aws/lambda/chikwex-cw-demo`
3. Set time range to **Last 30 minutes**
4. Paste each query below and click **Run query**

#### Query 1 – Error Rate Per Minute
```
fields @timestamp, @message
| filter @message like /"level":"ERROR"/
| stats count() as error_count by bin(1m) as minute
| sort minute asc
```
Shows how many ERROR-level entries occurred each minute.

#### Query 2 – Average Response Time
```
fields @timestamp, @message
| parse @message '"response_time":*,' as response_time
| filter ispresent(response_time)
| stats avg(response_time) as avg_ms,
        max(response_time) as max_ms,
        min(response_time) as min_ms,
        count() as total_requests
```
Extracts the `response_time` value from every log line and computes statistics.

#### Query 3 – Top 5 Error Codes
```
fields @timestamp, @message
| parse @message '"error_code":*,' as error_code
| filter ispresent(error_code)
| stats count() as occurrences by error_code
| sort occurrences desc
| limit 5
```
Shows the five most frequent HTTP error codes.

#### Query 4 – Failed Requests by user_id
```
fields @timestamp, @message
| parse @message '"user_id":"*"' as user_id
| parse @message '"level":"*"' as level
| filter level = "ERROR"
| stats count() as failed_requests by user_id
| sort failed_requests desc
```
Shows which users experienced the most failures.

---

### Step 7 – Verify Custom Metrics

1. Open [Custom Metrics – chikwex/AppMetrics](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2:graph=~();namespace=chikwex~2FAppMetrics)
2. You should see three metrics:
   - `HTTP500ErrorCount` — count of HTTP 500 responses
   - `SlowRequestCount` — count of WARN-level (slow) requests
   - `ResponseTime` — actual response time values in milliseconds
3. Click each metric and select **Add to graph** to visualize it

> These metrics are populated by the **Metric Filters** attached to the log group. Each filter pattern matches lines in the log and extracts a value. `ResponseTime` uses `$.response_time` as its value, which tells CloudWatch to extract the actual number rather than just counting +1.

---

### Step 8 – Verify CloudWatch Alarms

1. Open [CloudWatch Alarms](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:)
2. Both alarms should be visible:

| Alarm | Threshold | State |
|---|---|---|
| `chikwex-high-error-rate` | HTTP500ErrorCount > 3 in 5 min | `OK` or `ALARM` |
| `chikwex-high-response-time` | Avg ResponseTime > 1000ms in 5 min | `OK` or `ALARM` |

3. If either alarm is in `ALARM` state, check your email for the SNS notification

> **Why these thresholds?** The error rate alarm uses an absolute count of 3 HTTP-500 errors in 5 minutes. Given ~15 errors per 100 invocations, if you invoke rapidly you may trigger it. The response time alarm fires if the average latency in a 5-minute window exceeds 1000ms — WARN-level invocations can reach 2000ms which will pull the average up.

---

### Step 9 – Teardown (when done)

Removes all resources to avoid ongoing charges:

```bash
python teardown.py
```

Deletes in this order: Alarms → Metric Filters → Lambda → Log Group → SNS Topic → IAM Role.

---

## How Metric Filters Work

```
Log line (raw):
  {"level":"ERROR","user_id":"user_001","response_time":312,"error_code":500,...}

Filter: { $.error_code = 500 }
  └─► Match! Emit value "1" to metric HTTP500ErrorCount

Filter: { $.level = "WARN" }
  └─► No match (level is ERROR). Nothing emitted.

Filter: { $.response_time > 0 }
  └─► Match! Emit value $.response_time = 312 to metric ResponseTime
```

CloudWatch processes each log event against every filter. Matched events increment (or set) the corresponding custom metric data point.

---

## Console Links Quick Reference

| Console Page | URL |
|---|---|
| Lambda function | https://us-east-1.console.aws.amazon.com/lambda/home?region=us-east-1#/functions/chikwex-cw-demo |
| Log group | https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Fchikwex-cw-demo |
| Logs Insights | https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:logs-insights |
| Custom metrics | https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2:graph=~();namespace=chikwex~2FAppMetrics |
| Alarms | https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2: |
| SNS subscriptions | https://us-east-1.console.aws.amazon.com/sns/v3/home?region=us-east-1#/subscriptions |
| IAM role | https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/roles/chikwex-cw-lambda-role |

---

## Success Criteria Checklist

- [ ] `setup.py` completes without errors
- [ ] SNS email subscription is confirmed
- [ ] `invoke.py` completes 100 invocations
- [ ] Log group `/aws/lambda/chikwex-cw-demo` has log streams with JSON entries
- [ ] All 4 Logs Insights queries return results
- [ ] `chikwex/AppMetrics` namespace shows all 3 custom metrics
- [ ] Both CloudWatch alarms exist (state: OK, ALARM, or INSUFFICIENT_DATA)
- [ ] Alarm email received if thresholds were breached
