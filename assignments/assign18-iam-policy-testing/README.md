# Assignment 18 — IAM Policy Testing and Validation

## Overview

End-to-end IAM policy design, enforcement, and validation for a developer persona. A restrictive custom IAM policy limits `developer-test` to read-only S3 access on `Team:Dev` tagged buckets, EC2 launches restricted to `t2.micro`/`t3.micro` in a designated dev VPC, and full deny of production-tagged resources. A permission boundary enforces an absolute ceiling on privileges. An SCP guards the test OU against region sprawl and CloudTrail tampering. All policies are validated using the IAM Policy Simulator, Access Analyzer, and live assume-role session policy tests.

---

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────┐
│                         AWS Account (test OU)                        │
│                                                                      │
│   SCP ──► Deny non us-east-1/eu-west-1 regions                      │
│        ──► Deny CloudTrail deletion                                   │
│                                                                      │
│   ┌─────────────────────────┐                                        │
│   │  IAM User: developer-test│                                       │
│   │  PermissionBoundary ──► caps S3 read, EC2 micro, no IAM write   │
│   │  AttachedPolicy ─────► developer-policy (custom)                │
│   └────────────┬────────────┘                                        │
│                │ sts:AssumeRole                                      │
│   ┌────────────▼────────────┐                                        │
│   │  IAM Role: developer-role│                                       │
│   │  + session policy        │  (further restricts to describe-only) │
│   └─────────────────────────┘                                        │
│                                                                      │
│   IAM Access Analyzer (ACCOUNT)                                      │
│        └──► EventBridge ──► SNS ──► Email alert                     │
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
| `ec2:RunInstances` | Yes | `InstanceType` = t2.micro or t3.micro |
| `ec2:TerminateInstances`, `ec2:CreateSecurityGroup` | Yes | Within dev VPC only |
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

Exception: `OrganizationAccountAccessRole` and `AWSControlTowerExecution` are exempt from region restriction to allow management operations.

### Session Policy (`policies/session_policy.json`)

Injected at `sts:AssumeRole` time. Limits the assumed-role session to:
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
│   ├── developer_policy.json    # Custom developer policy (templatefile for VPC ID)
│   ├── permission_boundary.json # Absolute permission ceiling
│   ├── scp_restrictions.json    # SCP for test OU
│   └── session_policy.json      # Session policy used when assuming role
├── scripts/
│   ├── test_policy_simulator.py # Runs 6 policy simulator test cases
│   ├── test_assume_role.py      # Assumes role + session policy, runs 4 live tests
│   └── run_access_analyzer.py   # Queries findings + validates policy document
└── screenshots/
    └── (evidence captured during deployment)
```

---

## Deployment

### Prerequisites
- AWS CLI configured with admin credentials
- Terraform >= 1.5
- Python 3.9+ with `boto3` installed (`pip install boto3`)
- An existing VPC ID to use as the dev VPC

### 1 — Update VPC ID

Edit [terraform/terraform.tfvars](terraform/terraform.tfvars):
```
dev_vpc_id = "vpc-0abcdef1234567890"
```

### 2 — Apply Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Key outputs after apply:

```
developer_user_arn      = arn:aws:iam::123456789012:user/developer-test
developer_role_arn      = arn:aws:iam::123456789012:role/chikwex-assign18-developer-role
developer_policy_arn    = arn:aws:iam::123456789012:policy/chikwex-assign18-developer-policy
permission_boundary_arn = arn:aws:iam::123456789012:policy/chikwex-assign18-permission-boundary
access_analyzer_arn     = arn:aws:access-analyzer:us-east-1:123456789012:analyzer/chikwex-assign18-account-analyzer
```

Retrieve credentials (sensitive):
```bash
terraform output -raw access_key_id
terraform output -raw secret_access_key
```

### 3 — Apply SCP (Manual — requires AWS Organizations)

```bash
# Create the SCP in your organization
aws organizations create-policy \
  --name "chikwex-assign18-region-cloudtrail-deny" \
  --type SERVICE_CONTROL_POLICY \
  --content file://policies/scp_restrictions.json \
  --description "Deny non-approved regions and CloudTrail deletion"

# Attach to your test OU (replace ou-xxxx-xxxxxxxx with your OU ID)
aws organizations attach-policy \
  --policy-id p-xxxxxxxxxx \
  --target-id ou-xxxx-xxxxxxxx
```

---

## Testing

### IAM Policy Simulator

```bash
# Get policy ARNs from terraform output
POLICY_ARN=$(cd terraform && terraform output -raw developer_policy_arn)
BOUNDARY_ARN=$(cd terraform && terraform output -raw permission_boundary_arn)

python scripts/test_policy_simulator.py \
  --policy-arn "$POLICY_ARN" \
  --boundary-arn "$BOUNDARY_ARN"
```

Expected output:
```
=== IAM Policy Simulator Results ===

  [PASS] Can list S3 buckets
  [PASS] Cannot delete S3 objects
  [PASS] Can launch t2.micro instance
  [PASS] Cannot launch t2.large instance
  [PASS] Cannot access production-tagged resource
  [PASS] S3 read allowed on Team:Dev tagged bucket

Results: 6 passed, 0 failed
```

### Assume Role + Session Policy

```bash
ROLE_ARN=$(cd terraform && terraform output -raw developer_role_arn)

# Run as developer-test user (configure profile or env vars with developer-test credentials)
AWS_PROFILE=developer-test python scripts/test_assume_role.py \
  --role-arn "$ROLE_ARN"
```

Expected output:
```
=== Assume-Role + Session Policy Results ===

  [PASS] s3:ListAllMyBuckets (should ALLOW)  →  ALLOWED
  [PASS] ec2:DescribeInstances (should ALLOW) →  ALLOWED
  [PASS] s3:DeleteObject (should DENY)        →  DENIED
  [PASS] ec2:RunInstances t2.large (should DENY) →  DENIED

Results: 4 passed, 0 failed
```

### Access Analyzer

```bash
ANALYZER_ARN=$(cd terraform && terraform output -raw access_analyzer_arn)
POLICY_ARN=$(cd terraform && terraform output -raw developer_policy_arn)

python scripts/run_access_analyzer.py \
  --analyzer-arn "$ANALYZER_ARN" \
  --policy-arn "$POLICY_ARN"
```

Expected output:
```
=== Access Analyzer Findings ===
  [PASS] No active findings — account has no public external access

=== Policy Validation (chikwex-assign18-developer-policy) ===
  [PASS] No policy validation findings — policy is well-formed
```

---

## Policy Simulator Test Cases

| Test | Action | Expected | Reason |
|---|---|---|---|
| List S3 buckets | `s3:ListAllMyBuckets` | Allow | Explicitly allowed, no condition |
| Delete S3 object | `s3:DeleteObject` | Deny | Explicit Deny in developer policy |
| Launch t2.micro | `ec2:RunInstances` + t2.micro | Allow | InstanceType condition satisfied |
| Launch t2.large | `ec2:RunInstances` + t2.large | Deny | InstanceType condition not met |
| Access prod resource | `s3:GetObject` + Environment=production | Deny | Explicit Deny on production tag |
| Read Dev-tagged S3 | `s3:GetObject` + Team=Dev | Allow | Tag condition satisfied |

---

## Success Criteria

| Criterion | Status |
|---|---|
| Policies enforce correct restrictions | Verified via Policy Simulator |
| Policy Simulator confirms permissions | 6/6 test cases pass |
| User cannot exceed boundaries | Permission boundary blocks IAM escalation and production access |
| Access Analyzer shows no public access | Confirmed — ACCOUNT analyzer reports no active findings |
| Session policy restricts assumed-role session | Assume-role tests confirm describe-only scope |

---

## Teardown

```bash
cd terraform
terraform destroy
```

Detach and delete the SCP manually in AWS Organizations console or CLI before destroy if attached.
