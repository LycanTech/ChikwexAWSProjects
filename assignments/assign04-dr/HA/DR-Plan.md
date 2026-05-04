# Disaster Recovery Plan - Assignment 4

## 1. Architecture Overview

| Component | Primary (us-east-1) | DR (us-east-2) |
|-----------|---------------------|-----------------|
| VPC | vpc-004d871072ca79b9c (10.0.0.0/16) | New VPC (10.1.0.0/16) |
| EC2 Web Server | chikwex-dr-web-primary (54.159.102.36) | chikwex-dr-web-dr (3.149.229.16) |
| RDS PostgreSQL | chikwex-dr-db-primary | chikwex-dr-db-dr-replica (read replica) |
| DynamoDB | chikwex-dr-app-data | Global Table replica |
| S3 | chikwex-dr-app-data-866934333672-primary | chikwex-dr-app-data-866934333672-dr (CRR) |
| Route 53 | Failover routing: app.chikwex-dr.internal | Auto-failover on health check failure |

## 2. RTO and RPO Objectives

### Recovery Time Objective (RTO)

| Tier | Target RTO | Component | Strategy |
|------|-----------|-----------|----------|
| Tier 1 | < 5 minutes | DynamoDB | Global Tables (active-active, automatic) |
| Tier 1 | < 5 minutes | S3 Data | Cross-Region Replication (near real-time) |
| Tier 2 | < 15 minutes | Web Server (EC2) | Route 53 failover + standby EC2 in DR |
| Tier 2 | < 15 minutes | RDS Database | Promote read replica to standalone |
| Tier 3 | < 60 minutes | Full application stack | Complete failover with DNS propagation |

### Recovery Point Objective (RPO)

| Component | RPO | Method |
|-----------|-----|--------|
| DynamoDB | ~0 (seconds) | Global Tables with real-time replication |
| S3 | < 15 minutes | Cross-Region Replication (async) |
| RDS | < 5 minutes | Cross-region read replica (async replication) |
| EC2/EBS | < 24 hours | Daily automated backups via AWS Backup |

## 3. Backup Strategy

### AWS Backup Plans

| Plan | Schedule | Retention | Scope |
|------|----------|-----------|-------|
| Daily | 3:00 AM UTC daily | 7 days | EC2, DynamoDB (tag: Backup=daily) |
| Weekly | 5:00 AM UTC Sundays | 30 days | All primary resources (tag: Environment=primary) |
| Monthly | 6:00 AM UTC 1st of month | 365 days (cold storage after 90 days) | All primary resources |

### Additional Backups
- **RDS Automated Snapshots**: 7-day retention (native RDS feature)
- **Lambda Snapshot Manager**: Creates tagged manual snapshots daily at 2 AM UTC, auto-cleans after 7 days
- **S3 Versioning**: Enabled on all buckets, old versions expire after 90 days

## 4. Data Replication Summary

| Data Source | Replication Method | Direction | Lag |
|-------------|-------------------|-----------|-----|
| RDS PostgreSQL | Cross-region read replica | us-east-1 → us-east-2 | < 5 min |
| DynamoDB | Global Tables | Bidirectional | < 1 sec |
| S3 | Cross-Region Replication | us-east-1 → us-east-2 | < 15 min |
| RDS Snapshots | Lambda cross-region copy | us-east-1 → us-east-2 | Daily |

## 5. Monitoring and Alerting

### EventBridge Rules
- **Backup Failure Monitor**: Alerts on AWS Backup job failures/aborts
- **RDS Event Monitor**: Alerts on RDS failover, failure, and notification events
- **Snapshot Schedule**: Triggers Lambda snapshot function daily at 2 AM UTC

### CloudWatch (via StackSets - both regions)
- EC2 CPU utilization alarm (threshold: 80%)
- EC2 status check failure alarm
- Regional dashboards with EC2 and RDS metrics

### Notifications
- All alerts sent to SNS topic → chikwe.azinge@techconsulting.tech

---

# Backup and Recovery Runbook

## Procedure 1: Failover to DR Region

### Pre-conditions
- Primary region (us-east-1) is experiencing an outage
- Route 53 health checks have detected the failure
- DR region (us-east-2) resources are healthy

### Automatic Failover (Route 53)
1. Route 53 health check detects primary EC2 is unreachable (3 consecutive failures, ~90 seconds)
2. DNS automatically resolves `app.chikwex-dr.internal` to DR IP (3.149.229.16)
3. Traffic flows to DR web server

### Manual Steps Required
4. **Promote RDS Read Replica** to standalone database:
   ```bash
   aws rds promote-read-replica \
     --db-instance-identifier chikwex-dr-db-dr-replica \
     --region us-east-2
   ```
5. **Verify DynamoDB Global Table** is serving from us-east-2:
   ```bash
   aws dynamodb describe-table \
     --table-name chikwex-dr-app-data \
     --region us-east-2 \
     --query "Table.TableStatus"
   ```
6. **Update application configuration** to point to new RDS endpoint (DR region)
7. **Verify S3 data** is accessible in DR bucket:
   ```bash
   aws s3 ls s3://chikwex-dr-app-data-866934333672-dr --region us-east-2
   ```
8. **Notify stakeholders** of failover completion

## Procedure 2: Failback to Primary Region

### Pre-conditions
- Primary region (us-east-1) has recovered
- DR region is currently serving traffic

### Steps
1. **Verify primary region health**:
   ```bash
   curl http://54.159.102.36/health
   ```
2. **Re-create RDS in primary** (if needed) from latest snapshot:
   ```bash
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier chikwex-dr-db-primary \
     --db-snapshot-identifier <latest-snapshot-id> \
     --region us-east-1
   ```
3. **Re-establish RDS replication** from primary to DR
4. **Verify S3 replication** is active:
   ```bash
   aws s3api get-bucket-replication \
     --bucket chikwex-dr-app-data-866934333672-primary \
     --region us-east-1
   ```
5. **Switch Route 53** back to primary by ensuring primary health check passes
6. **Monitor** for 30 minutes to confirm stability
7. **Notify stakeholders** of failback completion

## Procedure 3: Restore from AWS Backup

### Restore EC2 Instance
```bash
aws backup start-restore-job \
  --recovery-point-arn <recovery-point-arn> \
  --iam-role-arn <backup-role-arn> \
  --metadata '{"SubnetId":"<subnet-id>","SecurityGroupIds":"<sg-id>"}' \
  --region us-east-1
```

### Restore RDS from Snapshot
```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier chikwex-dr-db-restored \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.t3.micro \
  --region us-east-1
```

### Restore DynamoDB from Point-in-Time
```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name chikwex-dr-app-data \
  --target-table-name chikwex-dr-app-data-restored \
  --use-latest-restorable-time \
  --region us-east-1
```

---

# Failover Testing Report

## Test 1: Route 53 DNS Failover

| Item | Details |
|------|---------|
| **Test Date** | [TO BE FILLED AFTER TESTING] |
| **Objective** | Verify automatic DNS failover when primary becomes unhealthy |
| **Method** | Stop Apache on primary EC2 to trigger health check failure |
| **Command** | `aws ec2 stop-instances --instance-ids <primary-instance-id> --region us-east-1` |
| **Expected Result** | Route 53 resolves to DR IP within ~90 seconds |
| **Verification** | `dig app.chikwex-dr.internal` should return 3.149.229.16 |

## Test 2: RDS Read Replica Promotion

| Item | Details |
|------|---------|
| **Test Date** | [TO BE FILLED AFTER TESTING] |
| **Objective** | Verify RDS read replica can be promoted to standalone |
| **Method** | Promote read replica in us-east-2 |
| **Command** | `aws rds promote-read-replica --db-instance-identifier chikwex-dr-db-dr-replica --region us-east-2` |
| **Expected Result** | Replica becomes standalone writable database |
| **Verification** | `aws rds describe-db-instances --db-instance-identifier chikwex-dr-db-dr-replica --region us-east-2 --query "DBInstances[0].ReadReplicaSourceDBInstanceIdentifier"` returns null |

## Test 3: DynamoDB Global Table Failover

| Item | Details |
|------|---------|
| **Test Date** | [TO BE FILLED AFTER TESTING] |
| **Objective** | Verify DynamoDB data is accessible in DR region |
| **Method** | Write item in us-east-1, read from us-east-2 |
| **Write Command** | `aws dynamodb put-item --table-name chikwex-dr-app-data --item '{"PK":{"S":"TEST"},"SK":{"S":"FAILOVER"}}' --region us-east-1` |
| **Read Command** | `aws dynamodb get-item --table-name chikwex-dr-app-data --key '{"PK":{"S":"TEST"},"SK":{"S":"FAILOVER"}}' --region us-east-2` |
| **Expected Result** | Item readable from both regions within seconds |

## Test 4: S3 Cross-Region Replication

| Item | Details |
|------|---------|
| **Test Date** | [TO BE FILLED AFTER TESTING] |
| **Objective** | Verify S3 objects replicate to DR bucket |
| **Method** | Upload file to primary, verify it appears in DR |
| **Upload** | `aws s3 cp testfile.txt s3://chikwex-dr-app-data-866934333672-primary/ --region us-east-1` |
| **Verify** | `aws s3 ls s3://chikwex-dr-app-data-866934333672-dr/ --region us-east-2` |
| **Expected Result** | File appears in DR bucket within 15 minutes |

---

# Cost Analysis

## Monthly Cost Estimate (us-east-1 + us-east-2)

### Compute
| Resource | Region | Type | Estimated Monthly Cost |
|----------|--------|------|----------------------|
| EC2 Primary | us-east-1 | t3.micro | $8.47 |
| EC2 DR Standby | us-east-2 | t3.micro | $8.47 |
| **Subtotal** | | | **$16.94** |

### Database
| Resource | Region | Type | Estimated Monthly Cost |
|----------|--------|------|----------------------|
| RDS Primary | us-east-1 | db.t3.micro | $12.41 |
| RDS Read Replica | us-east-2 | db.t3.micro | $12.41 |
| RDS Storage (20GB) | Both | gp2 | $4.60 |
| DynamoDB | us-east-1 | PAY_PER_REQUEST | ~$1.00 (low traffic) |
| DynamoDB Global Table | us-east-2 | PAY_PER_REQUEST | ~$1.00 (replication) |
| **Subtotal** | | | **$31.42** |

### Storage
| Resource | Region | Type | Estimated Monthly Cost |
|----------|--------|------|----------------------|
| S3 Primary | us-east-1 | Standard | ~$0.50 |
| S3 DR | us-east-2 | Standard | ~$0.50 |
| S3 CRR Transfer | Cross-region | Data transfer | ~$0.20 |
| EBS Volumes | Both | gp3 | ~$3.20 |
| **Subtotal** | | | **$4.40** |

### Backup & DR Services
| Resource | Details | Estimated Monthly Cost |
|----------|---------|----------------------|
| AWS Backup | Vault storage + snapshots | ~$2.00 |
| Route 53 | Hosted zone + 2 health checks | $2.00 |
| KMS | 1 CMK + API calls | $1.03 |
| Lambda | Snapshot manager (~30 invocations) | ~$0.01 |
| EventBridge | Rules + events | ~$0.01 |
| SNS | Notifications | ~$0.01 |
| CloudWatch | Alarms + dashboards | ~$3.00 |
| **Subtotal** | | **$8.06** |

### Total Estimated Monthly Cost

| Category | Cost |
|----------|------|
| Compute | $16.94 |
| Database | $31.42 |
| Storage | $4.40 |
| Backup & DR Services | $8.06 |
| **TOTAL** | **~$60.82/month** |

### Cost Optimization Recommendations
1. **Use Reserved Instances** for EC2 and RDS to save 30-60%
2. **Stop DR EC2** when not testing (save $8.47/month)
3. **Use Savings Plans** for compute workloads
4. **Monitor DynamoDB** usage and switch to provisioned capacity if predictable
5. **Set S3 lifecycle policies** aggressively for non-critical data

---

## CloudFormation Stacks Summary

| Stack | Region | Template | Resources |
|-------|--------|----------|-----------|
| chikwex-dr-primary | us-east-1 | primary-infrastructure.yaml | VPC networking, EC2, RDS, DynamoDB, S3 |
| chikwex-dr-secondary | us-east-2 | dr-infrastructure.yaml | VPC, EC2 standby, RDS read replica, KMS |
| chikwex-dr-backup | us-east-1 | backup-plan.yaml | AWS Backup vault, 3 backup plans, IAM role |
| chikwex-dr-replication | us-east-2 | data-replication.yaml | DR S3 bucket, S3 replication IAM role |
| chikwex-dr-route53 | us-east-1 | route53-failover.yaml | Hosted zone, health checks, failover records |
| chikwex-dr-automation | us-east-1 | automation.yaml | Lambda, EventBridge rules, SNS topic |
| chikwex-dr-monitoring (StackSet) | Both | stackset-monitoring.yaml | CloudWatch alarms + dashboards |
