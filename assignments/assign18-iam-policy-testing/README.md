# Assignment 18 — IAM Policy Testing and Validation

## Overview

End-to-end IAM policy design, enforcement, and validation for a developer persona. A restrictive custom IAM policy limits `developer-test` to read-only S3 access on `Team:Dev` tagged buckets, EC2 launches restricted to `t2.micro`/`t3.micro` in a designated dev VPC, and full deny of production-tagged resources. A permission boundary enforces an absolute ceiling on privileges. An SCP guards the test OU against region sprawl and CloudTrail tampering. All policies are validated using the IAM Policy Simulator, Access Analyzer, and live assume-role session policy tests.

---

## Deployed Resources

| Resource | ARN / ID |
|---|---|
| IAM User | `arn:aws:iam::866934333672:user/developer-test` |
| Developer Policy | `arn:aws:iam::866934333672:policy/chikwex-assign18-developer-policy` |
| Permission Boundary | `arn:aws:iam::866934333672:policy/chikwex-assign18-permission-boundary` |
| IAM Role | `arn:aws:iam::866934333672:role/chikwex-assign18-developer-role` |
| Access Analyzer | `arn:aws:access-analyzer:us-east-1:866934333672:analyzer/chikwex-assign18-account-analyzer` |
| SNS Alert Topic | `arn:aws:sns:us-east-1:866934333672:chikwex-assign18-analyzer-alerts` |
| EventBridge Rule | `chikwex-assign18-analyzer-finding` |
| Dev VPC (restricted) | `vpc-0cb15b4ac6d08c041` |
| Region | `us-east-1` |

---

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────┐
│                    AWS Account 866934333672 (us-east-1)              │
│                                                                      │
│   SCP ──► Deny non us-east-1/eu-west-1 regions                      │
│        ──► Deny CloudTrail deletion / StopLogging                    │
│        ──► Deny GuardDuty disable                                    │
│                                                                      │
│   ┌──────────────────────────────────────────┐                       │
│   │  IAM User: developer-test                │                       │
│   │  PermissionBoundary: chikwex-assign18-   │                       │
│   │    permission-boundary                   │                       │
│   │  AttachedPolicy: chikwex-assign18-       │                       │
│   │    developer-policy                      │                       │
│   └───────────────────┬──────────────────────┘                       │
│                       │ sts:AssumeRole                               │
│   ┌───────────────────▼──────────────────────┐                       │
│   │  IAM Role: chikwex-assign18-developer-   │                       │
│   │  role + inline session policy            │                       │
│   │  (restricts to S3/EC2 describe-only)     │                       │
│   └──────────────────────────────────────────┘                       │
│                                                                      │
│   IAM Access Analyzer: chikwex-assign18-account-analyzer (ACCOUNT)  │
│        └──► EventBridge ──► SNS ──► chikwe.azinge@techconsulting.tech│
└──────────────────────────────────────────────────────────────────────┘
```

---

## Policy Summary

### Developer Policy (`policies/developer_policy.json`)

| Action | Allowed | Condition |
|---|---|---|
| `s3:GetObject`, `s3:ListBucket` | Yes | Resource tag `Team: Dev` |
| `s3:ListAllMyBuckets` | Yes | — |
| `s3:PutObject`, `s3:DeleteObject` | **No** | Explicit Deny |
| `ec2:RunInstances` | Yes | `InstanceType` = t2.micro or t3.micro only |
| `ec2:TerminateInstances`, `ec2:CreateSecurityGroup` | Yes | Within `vpc-0cb15b4ac6d08c041` only |
| Any action on `Environment: production` tagged resource | **No** | Explicit Deny |

### Permission Boundary (`policies/permission_boundary.json`)

Acts as a hard ceiling — even if the attached policy allowed more, the boundary prevents:
- IAM user/role/policy creation or mutation
- Removal of the boundary itself
- Any access to production-tagged resources

### SCP (`policies/scp_restrictions.json`)

Applied to the test OU in AWS Organizations:

| Rule | Effect |
|---|---|
| Requests outside `us-east-1` and `eu-west-1` | Deny |
| `cloudtrail:DeleteTrail`, `StopLogging`, `UpdateTrail` | Deny |
| `guardduty:DeleteDetector` | Deny |
| Root account usage | Deny |

Exception carve-outs: `OrganizationAccountAccessRole` and `AWSControlTowerExecution` are exempt from the region restriction to allow management operations.

### Session Policy (`policies/session_policy.json`)

Injected at `sts:AssumeRole` time. Further restricts the assumed-role session to:
- `s3:GetObject`, `s3:ListBucket`, `s3:ListAllMyBuckets`
- `ec2:DescribeInstances`, `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups`

Session policies can only *restrict* — they cannot grant permissions not already in the role.

---

## Project Structure

```text
assign18-iam-policy-testing/
├── README.md
├── terraform/
│   ├── main.tf              # IAM user, role, policies, boundary, Access Analyzer, EventBridge
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars
├── policies/
│   ├── developer_policy.json    # Custom developer policy (ArnLike for VPC condition)
│   ├── permission_boundary.json # Absolute permission ceiling
│   ├── scp_restrictions.json    # SCP for test OU
│   └── session_policy.json      # Session policy used when assuming role
├── scripts/
│   ├── test_policy_simulator.py # Runs 6 policy simulator test cases
│   ├── test_assume_role.py      # Assumes role + session policy, runs 4 live tests
│   └── run_access_analyzer.py   # Queries findings + validates policy document
└── screenshots/
    └── (evidence captured from AWS Console)
```

---

## Deployment

### Prerequisites
- AWS CLI configured with admin credentials
- Terraform >= 1.5
- Python 3.9+ with `boto3` (`pip install boto3`)

### Apply Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Actual outputs from deployment:

```
developer_user_arn      = arn:aws:iam::866934333672:user/developer-test
developer_role_arn      = arn:aws:iam::866934333672:role/chikwex-assign18-developer-role
developer_policy_arn    = arn:aws:iam::866934333672:policy/chikwex-assign18-developer-policy
permission_boundary_arn = arn:aws:iam::866934333672:policy/chikwex-assign18-permission-boundary
access_analyzer_arn     = arn:aws:access-analyzer:us-east-1:866934333672:analyzer/chikwex-assign18-account-analyzer
sns_topic_arn           = arn:aws:sns:us-east-1:866934333672:chikwex-assign18-analyzer-alerts
```

### Apply SCP (Manual — requires AWS Organizations)

```bash
aws organizations create-policy \
  --name "chikwex-assign18-region-cloudtrail-deny" \
  --type SERVICE_CONTROL_POLICY \
  --content file://policies/scp_restrictions.json \
  --description "Deny non-approved regions and CloudTrail deletion"

# Attach to test OU
aws organizations attach-policy \
  --policy-id p-xxxxxxxxxx \
  --target-id ou-xxxx-xxxxxxxx
```

---

## Test Results

### IAM Policy Simulator — 6/6 PASS

```bash
python scripts/test_policy_simulator.py \
  --policy-arn arn:aws:iam::866934333672:policy/chikwex-assign18-developer-policy \
  --boundary-arn arn:aws:iam::866934333672:policy/chikwex-assign18-permission-boundary
```

```
=== IAM Policy Simulator Results ===

  [PASS] Can list S3 buckets
         action=s3:ListAllMyBuckets  expected=allowed  got=allowed
  [PASS] Cannot delete S3 objects
         action=s3:DeleteObject  expected=explicitDeny  got=explicitDeny
  [PASS] Can launch t2.micro instance
         action=ec2:RunInstances  expected=allowed  got=allowed
  [PASS] Cannot launch t2.large instance
         action=ec2:RunInstances  expected=implicitDeny  got=implicitDeny
  [PASS] Cannot access production-tagged resource
         action=s3:GetObject  expected=explicitDeny  got=explicitDeny
  [PASS] S3 read allowed on Team:Dev tagged bucket
         action=s3:GetObject  expected=allowed  got=allowed

Results: 6 passed, 0 failed
```

### Access Analyzer — PASS

```bash
python scripts/run_access_analyzer.py \
  --analyzer-arn arn:aws:access-analyzer:us-east-1:866934333672:analyzer/chikwex-assign18-account-analyzer \
  --policy-arn arn:aws:iam::866934333672:policy/chikwex-assign18-developer-policy
```

```
=== Access Analyzer Findings ===

  [PASS] No active findings — Access Analyzer confirms no public external access
  [PASS] Access Analyzer shows no public access findings

=== Policy Validation (chikwex-assign18-developer-policy) ===

  [PASS] No policy validation findings — policy is well-formed
```

---

## Policy Simulator Test Cases

| Test | Action | Expected | Result |
|---|---|---|---|
| List S3 buckets | `s3:ListAllMyBuckets` | Allow | PASS |
| Delete S3 object | `s3:DeleteObject` | Explicit Deny | PASS |
| Launch t2.micro | `ec2:RunInstances` + t2.micro | Allow | PASS |
| Launch t2.large | `ec2:RunInstances` + t2.large | Deny | PASS |
| Access prod resource | `s3:GetObject` + Environment=production | Explicit Deny | PASS |
| Read Dev-tagged S3 | `s3:GetObject` + Team=Dev | Allow | PASS |

---

## AWS Console Links

| Resource | Console URL |
|---|---|
| IAM User | `https://us-east-1.console.aws.amazon.com/iam/home#/users/details/developer-test` |
| Developer Policy | `https://us-east-1.console.aws.amazon.com/iam/home#/policies/arn:aws:iam::866934333672:policy/chikwex-assign18-developer-policy` |
| Permission Boundary | `https://us-east-1.console.aws.amazon.com/iam/home#/policies/arn:aws:iam::866934333672:policy/chikwex-assign18-permission-boundary` |
| IAM Role | `https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/chikwex-assign18-developer-role` |
| Policy Simulator | `https://policysim.aws.amazon.com/home/index.jsp?#users/developer-test` |
| Access Analyzer | `https://us-east-1.console.aws.amazon.com/access-analyzer/home?region=us-east-1#/analyzer/chikwex-assign18-account-analyzer` |
| SNS Topic | `https://us-east-1.console.aws.amazon.com/sns/v3/home?region=us-east-1#/topic/arn:aws:sns:us-east-1:866934333672:chikwex-assign18-analyzer-alerts` |
| EventBridge Rule | `https://us-east-1.console.aws.amazon.com/events/home?region=us-east-1#/eventbus/default/rules/chikwex-assign18-analyzer-finding` |

---

## Success Criteria

| Criterion | Status |
|---|---|
| Policies enforce correct restrictions | Verified via Policy Simulator (6/6 PASS) |
| Policy Simulator confirms permissions | 6/6 test cases pass |
| User cannot exceed boundaries | Permission boundary blocks IAM escalation and production access |
| Access Analyzer shows no public access | Confirmed — ACCOUNT analyzer reports 0 active findings |
| Session policy restricts assumed-role session | Session policy limits scope to S3/EC2 describe-only |

---

## Teardown

```bash
cd terraform
terraform destroy
```

Detach and delete the SCP in AWS Organizations before running destroy if it was applied.
