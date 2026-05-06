# Assignment 4 — Disaster Recovery & Backup Strategy

## Overview

A comprehensive multi-region disaster recovery solution covering automated backups, cross-region data replication, Route 53 DNS failover, and CloudFormation StackSets for synchronized infrastructure across two AWS regions.

- **Primary region**: `us-east-1`
- **DR region**: `us-east-2`
- **Naming prefix**: `chikwex-dr-`

---

## Architecture

```
                      us-east-1 (Primary)          us-east-2 (DR)
                    ┌─────────────────────┐      ┌──────────────────────┐
                    │  VPC 10.0.0.0/16    │      │  VPC 10.1.0.0/16     │
                    │                     │      │                      │
                    │  EC2 Web Server     │      │  EC2 Standby         │
                    │  54.159.102.36      │      │  3.149.229.16        │
                    │                     │      │                      │
                    │  RDS PostgreSQL  ───┼──────┼──► RDS Read Replica  │
                    │  (Primary)          │      │                      │
                    │                     │      │                      │
                    │  DynamoDB ◄─────────┼──────┼──► DynamoDB (Global) │
                    │  (active-active)    │      │   (active-active)    │
                    │                     │      │                      │
                    │  S3 Primary  ───────┼──CRR─┼──► S3 DR            │
                    └─────────────────────┘      └──────────────────────┘
                              │
                         Route 53
                    (Failover Routing Policy)
                    Health check → auto DNS switch
```

---

## RTO / RPO Objectives

| Component | RTO | RPO | Strategy |
| --- | --- | --- | --- |
| DynamoDB | < 5 min | ~0 sec | Global Tables (active-active) |
| S3 | < 5 min | < 15 min | Cross-Region Replication |
| Web Server (EC2) | < 15 min | < 24 hr | Route 53 failover + standby EC2 |
| RDS Database | < 15 min | < 5 min | Promote read replica to standalone |
| Full stack | < 60 min | < 5 min | Complete failover with DNS propagation |

---

## Resources Deployed

### CloudFormation Stacks

| Stack | Region | Template | What it creates |
| --- | --- | --- | --- |
| `chikwex-dr-primary` | us-east-1 | `primary-infrastructure.yaml` | VPC, EC2, RDS, DynamoDB, S3 |
| `chikwex-dr-secondary` | us-east-2 | `dr-infrastructure.yaml` | VPC, EC2 standby, RDS read replica, KMS |
| `chikwex-dr-backup` | us-east-1 | `backup-plan.yaml` | AWS Backup vault, 3 backup plans, IAM role |
| `chikwex-dr-replication` | us-east-2 | `data-replication.yaml` | DR S3 bucket, replication IAM role |
| `chikwex-dr-route53` | us-east-1 | `route53-failover.yaml` | Hosted zone, health checks, failover records |
| `chikwex-dr-automation` | us-east-1 | `automation.yaml` | Lambda, EventBridge rules, SNS topic |
| `chikwex-dr-monitoring` (StackSet) | Both | `stackset-monitoring.yaml` | CloudWatch alarms + dashboards |

### Key Resource IDs

| Resource | Primary (us-east-1) | DR (us-east-2) |
| --- | --- | --- |
| VPC | `vpc-004d871072ca79b9c` | New VPC |
| EC2 | `chikwex-dr-web-primary` — `54.159.102.36` | `chikwex-dr-web-dr` — `3.149.229.16` |
| RDS | `chikwex-dr-db-primary` | `chikwex-dr-db-dr-replica` |
| DynamoDB | `chikwex-dr-app-data` | Global Table replica |
| S3 | `chikwex-dr-app-data-866934333672-primary` | `chikwex-dr-app-data-866934333672-dr` |

---

## Backup Strategy

| Plan | Schedule | Retention | Scope |
| --- | --- | --- | --- |
| Daily | 3:00 AM UTC | 7 days | EC2, DynamoDB (tag: `Backup=daily`) |
| Weekly | 5:00 AM UTC Sundays | 30 days | All primary resources |
| Monthly | 6:00 AM UTC, 1st of month | 365 days (cold after 90 days) | All primary resources |

Additional:
- **RDS Automated Snapshots** — 7-day retention
- **Lambda Snapshot Manager** — daily manual snapshots at 2 AM UTC, auto-cleaned after 7 days
- **S3 Versioning** — enabled on all buckets, old versions expire after 90 days

---

## Deployment

### Prerequisites

- AWS CLI configured with credentials for both regions
- CloudFormation access in `us-east-1` and `us-east-2`
- StackSets service role configured for multi-region deployment

### Deploy order

```bash
# 1. Primary infrastructure
aws cloudformation deploy \
  --template-file HA/primary-infrastructure.yaml \
  --stack-name chikwex-dr-primary \
  --region us-east-1 \
  --capabilities CAPABILITY_IAM

# 2. DR infrastructure
aws cloudformation deploy \
  --template-file HA/dr-infrastructure.yaml \
  --stack-name chikwex-dr-secondary \
  --region us-east-2 \
  --capabilities CAPABILITY_IAM

# 3. Backup plans
aws cloudformation deploy \
  --template-file HA/backup-plan.yaml \
  --stack-name chikwex-dr-backup \
  --region us-east-1 \
  --capabilities CAPABILITY_IAM

# 4. Data replication (DR bucket + IAM)
aws cloudformation deploy \
  --template-file HA/data-replication.yaml \
  --stack-name chikwex-dr-replication \
  --region us-east-2 \
  --capabilities CAPABILITY_IAM

# 5. Route 53 failover routing
aws cloudformation deploy \
  --template-file HA/route53-failover.yaml \
  --stack-name chikwex-dr-route53 \
  --region us-east-1

# 6. Automation (Lambda + EventBridge)
aws cloudformation deploy \
  --template-file HA/automation.yaml \
  --stack-name chikwex-dr-automation \
  --region us-east-1 \
  --capabilities CAPABILITY_IAM

# 7. Monitoring StackSet (both regions)
aws cloudformation deploy \
  --template-file HA/stackset-monitoring.yaml \
  --stack-name chikwex-dr-monitoring \
  --region us-east-1
```

---

## Failover Runbook

### Automatic failover (Route 53)

Route 53 health checks detect primary EC2 is unreachable after 3 consecutive failures (~90 seconds). DNS automatically resolves to the DR IP `3.149.229.16`.

### Manual steps required after automatic failover

**1. Promote RDS read replica to standalone:**
```bash
aws rds promote-read-replica \
  --db-instance-identifier chikwex-dr-db-dr-replica \
  --region us-east-2
```

**2. Verify DynamoDB Global Table is serving from DR:**
```bash
aws dynamodb describe-table \
  --table-name chikwex-dr-app-data \
  --region us-east-2 \
  --query "Table.TableStatus"
```

**3. Verify S3 data in DR bucket:**
```bash
aws s3 ls s3://chikwex-dr-app-data-866934333672-dr --region us-east-2
```

**4. Update application config** to point to new RDS endpoint in DR region.

**5. Notify stakeholders** of failover completion.

### Failback to primary

```bash
# 1. Verify primary health
curl http://54.159.102.36/health

# 2. Re-create RDS from latest snapshot (if needed)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier chikwex-dr-db-primary \
  --db-snapshot-identifier <latest-snapshot-id> \
  --region us-east-1

# 3. Re-establish replication primary → DR
# 4. Verify Route 53 health check passes for primary
# 5. Monitor for 30 minutes, then notify stakeholders
```

---

## Restore Procedures

### Restore EC2 from AWS Backup
```bash
aws backup start-restore-job \
  --recovery-point-arn <recovery-point-arn> \
  --iam-role-arn <backup-role-arn> \
  --metadata '{"SubnetId":"<subnet-id>","SecurityGroupIds":"<sg-id>"}' \
  --region us-east-1
```

### Restore RDS from snapshot
```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier chikwex-dr-db-restored \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.t3.micro \
  --region us-east-1
```

### Restore DynamoDB point-in-time
```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name chikwex-dr-app-data \
  --target-table-name chikwex-dr-app-data-restored \
  --use-latest-restorable-time \
  --region us-east-1
```

---

## Cost Estimate

| Category | Monthly Cost |
| --- | --- |
| Compute (EC2 × 2, t3.micro) | $16.94 |
| Database (RDS primary + replica, DynamoDB) | $31.42 |
| Storage (S3 × 2, EBS, CRR transfer) | $4.40 |
| Backup & DR Services (Backup, Route 53, KMS, CloudWatch) | $8.06 |
| **Total** | **~$60.82/month** |

**Cost optimization**: Stop DR EC2 when not actively testing (saves ~$8.47/month). Use Reserved Instances for 30–60% savings on compute and RDS.

---

## Documentation

Full DR plan, backup runbook, failover testing report, and cost analysis are in [HA/DR-Plan.md](HA/DR-Plan.md).
