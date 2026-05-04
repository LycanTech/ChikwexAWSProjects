# Assignment 10 – Auto Scaling Group with Lifecycle Hooks

Automatically installs and configures a web server on every EC2 instance launched by an ASG, using lifecycle hooks, Lambda, and SSM Run Command. No user data scripts. No manual SSH.

---

## Architecture

```
                        ┌─────────────────────────────────────────────────┐
                        │               Auto Scaling Group                 │
                        │  (chikwex-asg  |  min=1  desired=1  max=3)      │
                        └────────────────────┬────────────────────────────┘
                                             │ instance launches
                                             ▼
                        ┌─────────────────────────────────────────────────┐
                        │          Lifecycle Hook (Pending:Wait)           │
                        │  Instance paused — not yet serving traffic       │
                        └────────────────────┬────────────────────────────┘
                                             │ EventBridge event
                                             ▼
                        ┌─────────────────────────────────────────────────┐
                        │         Lambda: chikwex-configure-instance       │
                        │  1. Polls SSM until agent is Online              │
                        │  2. Sends AWS-RunShellScript via SSM:            │
                        │       - dnf install httpd stress                 │
                        │       - fetch instance metadata (IMDSv2)         │
                        │       - write unique index.html                  │
                        │       - systemctl enable/start httpd             │
                        │  3. CompleteLifecycleAction → CONTINUE/ABANDON   │
                        └────────────────────┬────────────────────────────┘
                                             │ CONTINUE
                                             ▼
                        ┌─────────────────────────────────────────────────┐
                        │           Instance moves to InService            │
                        │      curl http://<PUBLIC_IP>/ → unique page      │
                        └─────────────────────────────────────────────────┘

CPU > 60% for 4 min
         │
         ▼
CloudWatch Alarm → Step Scaling Policy → +1 instance → lifecycle hook fires again
```

---

## Files

```
Assignment10/
├── main.tf          # All AWS resources
├── variables.tf     # Configurable values
├── outputs.tf       # Useful info + verification commands
├── lambda/
│   └── index.py     # Lambda that configures new instances via SSM
└── README.md
```

---

## Resources Created

| Resource | Name | Purpose |
|---|---|---|
| Launch Template | `chikwex-lt-*` | AL2023, t3.micro, SSM instance profile |
| Auto Scaling Group | `chikwex-asg` | min=1, max=3, desired=1 |
| Lifecycle Hook | `chikwex-launch-hook` | Pauses instance at Pending:Wait |
| Security Group | `chikwex-web-sg` | HTTP:80 inbound |
| IAM Role (EC2) | `chikwex-ec2-ssm-role` | AmazonSSMManagedInstanceCore |
| IAM Role (Lambda) | `chikwex-lambda-role` | SSM + ASG + CloudWatch Logs |
| Lambda Function | `chikwex-configure-instance` | Installs and configures httpd |
| EventBridge Rule | `chikwex-lifecycle-launch` | Routes lifecycle events to Lambda |
| CloudWatch Alarm | `chikwex-cpu-high` | CPU > 60% for 2 × 2min periods |
| Scaling Policy | `chikwex-scale-out` | Adds 1 instance when alarm fires |

---

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured (`aws configure`)
- IAM permissions to create EC2, Lambda, IAM, CloudWatch, EventBridge, SSM resources

---

## Deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment takes ~2 minutes. The first instance will finish configuring ~3-4 minutes after `apply` completes (SSM agent boot + command execution).

---

## Verify

### 1. Watch Lambda configure the first instance
```bash
aws logs tail /aws/lambda/chikwex-configure-instance --follow --region us-east-1
```

### 2. Get the instance public IP
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=chikwex-instance" "Name=instance-state-name,Values=running" \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output text
```

### 3. Check the web page
```bash
curl http://<PUBLIC_IP>/
```
Expected output: HTML page showing Instance ID, Availability Zone, Private IP, Instance Type, and Launch Time.

### 4. Trigger scale-out
SSH into the instance and run:
```bash
stress --cpu 4 --timeout 300 &
```
Then monitor:
```bash
# Watch the alarm flip to ALARM state
aws cloudwatch describe-alarms --alarm-names chikwex-cpu-high \
  --query "MetricAlarms[0].StateValue"

# Watch scale-out activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name chikwex-asg \
  --query "Activities[*].[StatusCode,Description]" --output table
```

### 5. Verify the new instance also auto-configured
Repeat step 2-3 for the new instance's IP. The page will show different metadata.

---

## How the Lifecycle Hook Works

When an instance launches, the ASG puts it in `Pending:Wait` state instead of immediately making it `InService`. The hook has a **600-second heartbeat timeout** — if Lambda does not call `CompleteLifecycleAction` within that window, the instance is automatically abandoned.

Lambda signals:
- `CONTINUE` — SSM command succeeded, instance joins the fleet as `InService`
- `ABANDON` — SSM failed or timed out, instance is terminated

This guarantees that **every instance in the fleet has httpd running before it can receive traffic**.

---

## Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | Deployment region |
| `project_name` | `chikwex` | Resource name prefix |
| `instance_type` | `t3.micro` | EC2 instance type |
| `asg_min_size` | `1` | Minimum instances |
| `asg_max_size` | `3` | Maximum instances |
| `asg_desired_capacity` | `1` | Initial count |
| `cpu_scale_out_threshold` | `60` | CPU % to trigger scale-out |
| `cpu_alarm_period_seconds` | `120` | CloudWatch evaluation period |
| `cpu_alarm_evaluation_periods` | `2` | Consecutive periods before alarm |
| `lifecycle_heartbeat_timeout` | `600` | Seconds before hook auto-abandons |

---

## Clean Up

```bash
terraform destroy
```

---

## Success Criteria

- [x] New instances automatically have a working web server (no manual intervention)
- [x] Scale-out happens within 5 minutes of CPU > 60%
- [x] All instances show unique metadata on their web page
