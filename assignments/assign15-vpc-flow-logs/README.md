# Assignment 15 — VPC Flow Logs Analysis with Athena

## Overview

This assignment deploys a complete AWS network traffic analysis pipeline. VPC Flow Logs capture all traffic in Parquet format to S3, and Amazon Athena is used to query the logs with saved SQL queries covering security analysis, protocol breakdowns, and traffic patterns.

---

## Architecture

```
                          ┌─────────────────────────────────────────────────┐
                          │               VPC (10.15.0.0/16)                │
                          │                                                   │
  Your IP ───SSH──►  ┌────┴──────────────────┐   ┌───────────────────────┐  │
  98.192.38.196/32   │   Public Subnet        │   │   Private Subnet      │  │
                     │   10.15.1.0/24 (us-e1a)│   │   10.15.2.0/24 (us-e1b)│ │
                     │                        │   │                       │  │
                     │  ┌─────────────────┐   │   │  ┌─────────────────┐ │  │
                     │  │ Public EC2      │◄──┼───┼─►│ Private EC2     │ │  │
                     │  │ i-06891419e362  │   │   │  │ i-0cb5a9a939de  │ │  │
                     │  │ 10.15.1.204     │   │   │  │ 10.15.2.35      │ │  │
                     │  │ 3.81.10.237     │   │   │  │ (no public IP)  │ │  │
                     │  └────────┬────────┘   │   │  └─────────────────┘ │  │
                     └──────────┼────────────┘   └───────────────────────┘  │
                                │                                             │
                          ┌─────┴──────┐                                     │
                          │    IGW     │          VPC Flow Logs (ALL traffic) │
                          └─────┬──────┘                    │                │
                                │                           ▼                │
                          Internet                  ┌───────────────┐        │
                       (wget/curl tests)             │  S3 Bucket    │        │
                                                     │  Parquet fmt  │        │
                                                     └───────┬───────┘        │
                                                             │                 │
                                                             ▼
                                                     ┌───────────────┐
                                                     │    Athena     │
                                                     │  Workgroup +  │
                                                     │  6 Queries    │
                                                     └───────────────┘
```

---

## Resources Deployed

| Resource | Name / ID |
| --- | --- |
| VPC | `vpc-068ae6787731711a3` |
| Public Subnet | `subnet-05b92cc5168aa0481` (us-east-1a) |
| Private Subnet | `subnet-06e89b0706ccd814c` (us-east-1b) |
| Internet Gateway | `igw-04fd42498b75f3190` |
| Public EC2 | `i-06891419e3627a8d6` — `3.81.10.237` / `10.15.1.204` |
| Private EC2 | `i-0cb5a9a939deed016` — `10.15.2.35` (private only) |
| Public Security Group | `sg-0550f1a27b33f0f51` |
| Private Security Group | `sg-0dc071c9dcbb246e5` |
| VPC Flow Log | `fl-0a5633dd09ba4f30e` |
| S3 Flow Logs Bucket | `vpcflow-assign15-vpc-flow-logs-866934333672` |
| S3 Athena Results Bucket | `vpcflow-assign15-athena-results-866934333672` |
| Athena Workgroup | `vpcflow-assign15-workgroup` |
| Athena Database | `vpcflow_assign15_flow_logs_db` |

---

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity` returns your account)
- Terraform >= 1.5
- OpenSSH client

---

## Deployment

### 1. Generate SSH key pair
```bash
ssh-keygen -t rsa -b 4096 -f assign15-key -N ""
```

### 2. Get your public IP
```bash
curl -s https://checkip.amazonaws.com
```

### 3. Create `terraform.tfvars`
```hcl
aws_region       = "us-east-1"
project_name     = "vpcflow-assign15"
operator_ip_cidr = "<YOUR_IP>/32"
ec2_public_key   = "<contents of assign15-key.pub>"
```

### 4. Fix SSH key permissions (Windows)
```powershell
$keyPath = ".\assign15-key"
icacls $keyPath /inheritance:r
icacls $keyPath /grant:r "${env:USERNAME}:(R)"
```

### 5. Deploy
```bash
terraform init
terraform apply -auto-approve
```

### 6. Note the outputs
```
public_ec2_public_ip  = "3.81.10.237"
private_ec2_private_ip = "10.15.2.35"
ssh_command           = "ssh -i assign15-key ec2-user@3.81.10.237"
```

---

## Traffic Generation

Copy and run the traffic generator **from the public EC2** to produce all traffic patterns in the flow logs:

```bash
# Copy script to EC2
scp -i assign15-key traffic_generator.sh ec2-user@3.81.10.237:/home/ec2-user/

# SSH in and run it
ssh -i assign15-key ec2-user@3.81.10.237
chmod +x traffic_generator.sh
./traffic_generator.sh 10.15.2.35
```

### Traffic patterns generated

| Test | Protocol | Expected Flow Log Action |
| --- | --- | --- |
| Ping private EC2 × 60 packets | ICMP (protocol 1) | ACCEPT |
| SSH probe to private EC2 port 22 | TCP | ACCEPT (port allowed by SG) |
| Connection to port 8080 | TCP | REJECT (port blocked by SG) |
| Connection to port 443 | TCP | REJECT (port blocked by SG) |
| Connection to port 3389 | TCP | REJECT (port blocked by SG) |
| wget aws.amazon.com / example.com / httpbin.org | TCP outbound | ACCEPT |
| curl httpbin.org / ifconfig.me | TCP outbound | ACCEPT |

> Flow logs appear in S3 within approximately 10 minutes of traffic generation.

---

## Athena Setup

### Step 1 — Select workgroup
Open the [Athena Console](https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/workgroup/vpcflow-assign15-workgroup) and switch to workgroup `vpcflow-assign15-workgroup`.

### Step 2 — Create the table
Go to [Saved Queries](https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/saved-queries) and run:

```
vpcflow-assign15-create-flow-logs-table
```

This creates a partitioned external table in Parquet format with partition projection enabled — no `MSCK REPAIR TABLE` needed.

### Step 3 — Run the analysis queries

| Saved Query Name | What it finds |
| --- | --- |
| `vpcflow-assign15-top10-source-ips` | Top 10 source IPs by bytes transferred |
| `vpcflow-assign15-all-reject-actions` | All REJECT entries — blocked/refused connections |
| `vpcflow-assign15-traffic-between-ips` | Bidirectional traffic between two specific IPs |
| `vpcflow-assign15-connections-port-22` | All SSH attempts (ACCEPT and REJECT) |
| `vpcflow-assign15-traffic-by-protocol` | Volume breakdown by TCP / UDP / ICMP |
| `vpcflow-assign15-security-events-summary` | Sources with 5+ REJECTs — potential scanners |

---

## Key Design Decisions

### Why Parquet instead of plain text?
VPC Flow Logs default to space-delimited plain text. Parquet is a columnar binary format:
- Athena scans only the columns referenced in the query — typically 10–20x less data
- Snappy compression reduces storage size by ~70%
- Result: queries are ~15x cheaper and faster

### Why Hive-compatible partitions?
Setting `hive_compatible_partitions = true` on the flow log creates S3 prefixes like:
```
AWSLogs/.../year=2026/month=05/day=04/hour=14/
```
Athena can skip entire partitions when you filter by date, avoiding full-bucket scans.

### Why partition projection?
The `TBLPROPERTIES` block in the CREATE TABLE query enables partition projection — Athena computes valid partition paths mathematically instead of querying the Glue catalog. This eliminates the need to run `MSCK REPAIR TABLE` every time new hourly files arrive.

### Why is port 8080 blocked on the private SG?
The private security group intentionally has **no ingress rule for port 8080**, which causes TCP SYN packets to that port to be dropped. This produces `REJECT` entries in the flow logs, which are the most security-relevant events to query.

---

## Cost Estimate

| Component | Estimate |
| --- | --- |
| VPC Flow Log ingestion | < $0.01 |
| S3 storage (90-day lifecycle) | < $0.01/month |
| Athena — all 5 queries on Parquet data | < $0.01 |
| EC2 t3.micro × 2 (per hour) | ~$0.02/hr |
| **Total lab cost** | **~$0.15** |

Full breakdown in [cost_calculator.md](cost_calculator.md).

> Run `terraform destroy` immediately after completing the lab to stop EC2 and IGW charges.

---

## Cleanup

```bash
terraform destroy -auto-approve
```

This destroys all resources including both S3 buckets (`force_destroy = true` is set).

---

## AWS Console Links

### VPC & Networking

| Resource | Link |
| --- | --- |
| VPC (`vpc-068ae6787731711a3`) | https://us-east-1.console.aws.amazon.com/vpc/home?region=us-east-1#VpcDetails:VpcId=vpc-068ae6787731711a3 |
| Subnets | https://us-east-1.console.aws.amazon.com/vpc/home?region=us-east-1#subnets:filter=vpc-068ae6787731711a3 |
| VPC Flow Log (`fl-0a5633dd09ba4f30e`) | https://us-east-1.console.aws.amazon.com/vpc/home?region=us-east-1#FlowLogs:filter=vpc-068ae6787731711a3 |

### EC2 Instances

| Resource | Link |
| --- | --- |
| Public EC2 (`i-06891419e3627a8d6`) — `3.81.10.237` | https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Instances:instanceId=i-06891419e3627a8d6 |
| Private EC2 (`i-0cb5a9a939deed016`) — `10.15.2.35` | https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Instances:instanceId=i-0cb5a9a939deed016 |

### S3

| Resource | Link |
| --- | --- |
| Flow Logs bucket | https://s3.console.aws.amazon.com/s3/buckets/vpcflow-assign15-vpc-flow-logs-866934333672?region=us-east-1 |
| Athena results bucket | https://s3.console.aws.amazon.com/s3/buckets/vpcflow-assign15-athena-results-866934333672?region=us-east-1 |

### Athena

| Resource | Link |
| --- | --- |
| Workgroup (`vpcflow-assign15-workgroup`) | https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/workgroups/vpcflow-assign15-workgroup |
| Query Editor | https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/query-editor |
| Saved Queries | https://us-east-1.console.aws.amazon.com/athena/home?region=us-east-1#/saved-queries |
