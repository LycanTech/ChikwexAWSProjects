# Assignment 14 – EventBridge Automated Scheduler

Three EventBridge-driven Lambda functions that automate EC2 lifecycle management, snapshot housekeeping, and security-group auditing. All alerts and reports are delivered through a single SNS topic.

---

## Architecture

```
EventBridge Rules
│
├── rate(5 minutes)      → ec2_scheduler Lambda
│                              ↓
│                        Find EC2 instances tagged Environment=Dev
│                        9 AM  UTC → Start stopped instances
│                        6 PM+ UTC → Stop running instances
│                        Publish report → SNS
│
├── cron(0 2 ? * SUN *)  → snapshot_cleanup Lambda
│                              ↓
│                        Find all owned EBS snapshots
│                        Delete: untagged AND older than 30 days
│                        Publish summary report → SNS
│
└── rate(1 hour)         → security_check Lambda
                               ↓
                         Find SGs with 0.0.0.0/0 inbound on port 22
                         Publish alert → SNS
```

---

## Prerequisites

| Tool | Version |
|------|---------|
| Terraform | ≥ 1.5 |
| AWS CLI | ≥ 2.x (configured with appropriate credentials) |
| Python (local) | 3.12 (only needed for linting; Lambda runs in AWS) |

IAM permissions required to deploy:
- `lambda:*`
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PutRolePolicy`
- `events:*`
- `sns:*`
- `ec2:DescribeInstances`, `ec2:StartInstances`, `ec2:StopInstances`
- `ec2:DescribeSnapshots`, `ec2:DeleteSnapshot`
- `ec2:DescribeSecurityGroups`

---

## Files

```
Assign14/
├── main.tf                     # All AWS resources
├── variables.tf                # Input variables
├── outputs.tf                  # Output values
├── lambda/
│   ├── ec2_scheduler.py        # Rule 1: EC2 start/stop
│   ├── snapshot_cleanup.py     # Rule 2: EBS snapshot cleanup
│   └── security_check.py       # Rule 3: SSH security group audit
└── README.md
```

---

## Deployment

### 1. Configure variables

Edit `variables.tf` or create a `terraform.tfvars` file:

```hcl
aws_region              = "us-east-1"
project_name            = "chikwex"
alert_email             = "your@email.com"   # Replace before deploying
snapshot_retention_days = 30
```

### 2. Deploy

```bash
cd Assign14
terraform init
terraform plan
terraform apply
```

### 3. Confirm SNS subscription

After `apply`, AWS sends a confirmation email to `alert_email`. Click **Confirm subscription** to start receiving reports.

---

## Lambda Functions

### Rule 1 – EC2 Scheduler (`rate(5 minutes)`)

| Detail | Value |
|--------|-------|
| Trigger | Every 5 minutes |
| Tag filter | `Environment = Dev` |
| Start action | Hour == 9 UTC → start stopped instances |
| Stop action | Hour >= 18 UTC → stop running instances |
| Report | SNS – count started / stopped |

> **Timezone note:** all comparisons use UTC. Adjust `current_hour` checks in `ec2_scheduler.py` if a different timezone is needed.

### Rule 2 – Snapshot Cleanup (`cron(0 2 ? * SUN *)`)

| Detail | Value |
|--------|-------|
| Trigger | Every Sunday at 02:00 UTC |
| Scope | Snapshots owned by this account |
| Delete criteria | No tags **AND** older than `RETENTION_DAYS` (default 30) |
| Report | SNS – deleted list, error list |

> Snapshots with any tag are preserved regardless of age.

### Rule 3 – Security Check (`rate(1 hour)`)

| Detail | Value |
|--------|-------|
| Trigger | Every hour |
| Check | Inbound rule allowing `0.0.0.0/0` on TCP port 22 |
| Alert | SNS – list of offending SG IDs / names / VPC |

---

## Manual Testing

Manually invoke any rule from the AWS Console or CLI:

```bash
# Trigger EC2 scheduler now
aws lambda invoke \
  --function-name chikwex-ec2-scheduler \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Trigger snapshot cleanup now
aws lambda invoke \
  --function-name chikwex-snapshot-cleanup \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json

# Trigger security check now
aws lambda invoke \
  --function-name chikwex-security-check \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

You can also use **EventBridge → Rules → Test** in the AWS Console to trigger any rule manually.

---

## Cleanup

```bash
terraform destroy
```

This removes all Lambda functions, EventBridge rules, the SNS topic, and the IAM role. EBS snapshots that were **not** deleted by the cleanup Lambda are unaffected.

---

## Success Criteria

| Criterion | How to verify |
|-----------|---------------|
| Scheduled rules execute on time | CloudWatch Logs → `/aws/lambda/chikwex-*` |
| EC2 instances stop at 6 pm | Check instance state in EC2 console after 18:00 UTC |
| EC2 instances start at 9 am | Check instance state in EC2 console after 09:00 UTC |
| Reports sent via SNS | Email inbox receives JSON summary |
| Security alerts identify risky SGs | Create a test SG with 0.0.0.0/0 on port 22; confirm alert email |
