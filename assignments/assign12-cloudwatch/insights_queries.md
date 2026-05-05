# CloudWatch Logs Insights Queries
# Log Group: /aws/lambda/chikwex-cw-demo
# Run these in: CloudWatch → Logs Insights → select log group → paste query

---

## Query 1 – Error Rate Per Minute

```
fields @timestamp, @message
| filter @message like /\"level\":\"ERROR\"/
| stats count() as error_count by bin(1m) as minute
| sort minute asc
```

**What it shows:** How many ERROR-level log entries occurred each minute.
Useful for spotting spikes or sustained failure periods.

---

## Query 2 – Average Response Time

```
fields @timestamp, @message
| parse @message '"response_time":*,' as response_time
| filter ispresent(response_time)
| stats avg(response_time) as avg_ms,
        max(response_time) as max_ms,
        min(response_time) as min_ms,
        count() as total_requests
```

**What it shows:** Overall average, max, and min response times across all
100 invocations. The `parse` command extracts the numeric value from the JSON.

---

## Query 3 – Top 5 Error Codes

```
fields @timestamp, @message
| parse @message '"error_code":*,' as error_code
| filter ispresent(error_code)
| stats count() as occurrences by error_code
| sort occurrences desc
| limit 5
```

**What it shows:** The five most frequent HTTP error codes returned by the
Lambda, sorted by frequency. Helps identify the dominant failure type.

---

## Query 4 – Failed Requests by user_id

```
fields @timestamp, @message
| parse @message '"user_id":"*"' as user_id
| parse @message '"level":"*"' as level
| filter level = "ERROR"
| stats count() as failed_requests by user_id
| sort failed_requests desc
```

**What it shows:** Which simulated users experienced the most errors.
In a real system this helps you identify if failures are user-specific
(bad session, permissions) vs. global.

---

## How to run a query in the Console

1. Open **CloudWatch → Logs Insights**
2. Under **Select log group(s)** choose `/aws/lambda/chikwex-cw-demo`
3. Set time range to **Last 30 minutes** (or the window you invoked in)
4. Paste a query above → click **Run query**
