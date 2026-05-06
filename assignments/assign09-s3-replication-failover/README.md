# Assignment 9: Multi-Region S3 Replication with Failover

## Actual Results (Completed 2026-03-04)

| Test | Result | Status |
|---|---|---|
| Primary bucket | `enhanceit-primary-us-east-1` (us-east-1) | PASS |
| Replica bucket | `enhanceit-replica-eu-west-1` (eu-west-1) | PASS |
| CRR Rule 1 — `critical/` prefix | 10/10 files replicated | PASS |
| CRR Rule 2 — `replicate=true` tag | 10/10 files replicated | PASS |
| CloudWatch alarm | Threshold 900s on ReplicationLatency | PASS |
| Delete marker replication | Confirmed in replica | PASS |
| 500MB file replication lag | **3 min 24 sec** (< 15 min SLA) | PASS |
| RTO simulation | **3 seconds** to retrieve from replica | PASS |

---


---

## Step 1 — Create the Primary S3 Bucket (us-east-1)

1. Go to **AWS Console → S3 → Create Bucket**
2. Bucket name: e.g. `neha-primary-us-east-1`
3. Region: **us-east-1**
4. Leave Block Public Access ON
5. Click **Create bucket**

---

## Step 2 — Enable Versioning on Primary Bucket

1. Open the primary bucket → **Properties** tab
2. Scroll to **Bucket Versioning** → click **Edit**
3. Select **Enable** → Save changes

> Versioning is **required** for CRR to work.

---

## Step 3 — Create the Replica S3 Bucket (eu-west-1)

1. Go to **S3 → Create Bucket**
2. Bucket name: e.g. `neha-replica-eu-west-1`
3. Region: **eu-west-1 (Ireland)**
4. Enable **Versioning** on this bucket too (required for CRR destination)
5. Click **Create bucket**

---

## Step 4 — Configure Cross-Region Replication (CRR)

1. Open the **primary bucket** → **Management** tab
2. Under **Replication rules** → click **Create replication rule**
3. Rule name: `replicate-critical-prefix`
4. **Status**: Enabled
5. **Source**: Choose **Limit the scope** → enter prefix `critical/`
6. **Destination**: Choose the replica bucket (`neha-replica-eu-west-1`)
7. **IAM Role**: Choose **Create new role** (AWS will auto-create it)
8. Click **Save**

Then create a **second rule**:
1. Rule name: `replicate-tagged-objects`
2. **Source**: Filter by tag → Key: `replicate`, Value: `true`
3. Same destination bucket
4. Click **Save**

---

## Step 5 — Create a CloudWatch Alarm for Replication Metrics

1. Go to **CloudWatch → Alarms → Create Alarm**
2. Click **Select metric → S3 → Replication metrics**
3. Choose metric: `ReplicationLatency` for your primary bucket
4. Set condition: **Greater than 900 seconds** (15 min threshold)
5. Notification: Create an SNS topic or use an existing one (optional but good)
6. Alarm name: `S3ReplicationLagAlarm`
7. Click **Create alarm**

---

## Step 6 — Upload 20 Files and Verify Replication

Upload files in 3 batches to test both rules:

**Batch A — prefix rule** (should replicate):
```bash
for i in $(seq 1 10); do
  echo "file $i content" > file$i.txt
  aws s3 cp file$i.txt s3://neha-primary-us-east-1/critical/file$i.txt
done
```

**Batch B — tag rule** (should replicate):
```bash
for i in $(seq 11 20); do
  echo "file $i content" > file$i.txt
  aws s3 cp file$i.txt s3://neha-primary-us-east-1/other/file$i.txt \
    --metadata-directive REPLACE \
    --tagging "replicate=true"
done
```

**Verify replication** (wait a few minutes then run):
```bash
aws s3 ls s3://neha-replica-eu-west-1/critical/ --region eu-west-1
aws s3 ls s3://neha-replica-eu-west-1/other/ --region eu-west-1
```

---

## Step 7 — Delete an Object and Verify Delete Marker Replication

1. Delete an object from the primary bucket:
```bash
aws s3 rm s3://neha-primary-us-east-1/critical/file1.txt
```
2. Wait ~5 minutes, then check the replica:
```bash
aws s3api list-object-versions \
  --bucket neha-replica-eu-west-1 \
  --prefix critical/file1.txt \
  --region eu-west-1
```
Look for a `DeleteMarkers` entry in the output — that confirms delete markers are replicating.

---

## Step 8 — Test Replication Lag with a Large File (500MB)

Generate and upload a 500MB test file:
```bash
# Generate a 500MB file
dd if=/dev/urandom of=bigfile.bin bs=1M count=500

# Upload it
aws s3 cp bigfile.bin s3://neha-primary-us-east-1/critical/bigfile.bin

# Note the timestamp, then poll the replica
watch -n 30 'aws s3 ls s3://neha-replica-eu-west-1/critical/bigfile.bin --region eu-west-1'
```
Record the time from upload to when it appears in the replica — this is your **replication lag**.

---

## Step 9 — Calculate RTO by Simulating Primary Region Failure

1. **Simulate failure**: Stop uploading to / accessing the primary bucket
2. Switch your app (or manually run commands) to read from the replica:
```bash
aws s3 cp s3://neha-replica-eu-west-1/critical/file2.txt ./recovered.txt --region eu-west-1
```
3. **RTO** = time from when you "declared failure" to when you successfully retrieved an object from the replica
4. Document this time — the goal is under 15 minutes

---

## Success Criteria Checklist

| Criteria | How to verify |
|---|---|
| Replication within 15 min | Check CloudWatch `ReplicationLatency` metric |
| Delete markers replicate | `list-object-versions` on replica shows DeleteMarkers |
| Can retrieve from replica during "failure" | Successfully ran `s3 cp` from replica bucket |

---

## Suggested Project Structure

```
S3ReplicationFailover/
├── setup/
│   ├── create-buckets.sh       # Steps 1-3
│   ├── configure-crr.sh        # Step 4
│   └── create-cw-alarm.sh      # Step 5
├── test/
│   ├── upload-files.sh         # Steps 6
│   ├── test-delete-marker.sh   # Step 7
│   ├── test-large-file.sh      # Step 8
│   └── simulate-failover.sh    # Step 9
└── FailoverReplicationAssignment
```
