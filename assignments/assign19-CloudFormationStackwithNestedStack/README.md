# Assignment 19 — CloudFormation Stack with Nested Stacks

## Overview

Modular AWS infrastructure built with CloudFormation nested stacks. A single parent stack (`main-infrastructure.yaml`) orchestrates three child stacks — network, security, and compute — and passes outputs between them so each layer only receives the context it needs.

---

## Architecture

```
main-infrastructure.yaml (parent)
├── network-stack.yaml       → VPC, subnets, IGW, route table
├── security-stack.yaml      → Security Group, NACL  (receives VpcId)
└── compute-stack.yaml       → EC2 instances          (receives SubnetIds + SG)
```

### Environment differences

| Setting          | dev         | prod                    |
|------------------|-------------|-------------------------|
| Instance type    | t2.micro    | t3.medium               |
| Instance count   | 1           | 2 (across 2 subnets)    |
| Subnets created  | 1 public    | 2 public (multi-AZ)     |

---

## File Structure

```
assign19-CloudFormationStackwithNestedStack/
├── main-infrastructure.yaml   # Parent stack
├── network-stack.yaml         # Nested: VPC, subnets, IGW
├── security-stack.yaml        # Nested: Security Group, NACL
├── compute-stack.yaml         # Nested: EC2 instances
├── failure-test-stack.yaml    # Standalone: deliberate-failure rollback demo
└── README.md
```

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- An S3 bucket to host the nested templates (the parent stack fetches them from S3)

---

## Deployment

### Step 1 — Upload nested templates to S3

```bash
BUCKET=my-cfn-templates-bucket   # replace with your bucket name
REGION=us-east-1

aws s3 cp network-stack.yaml   s3://$BUCKET/network-stack.yaml
aws s3 cp security-stack.yaml  s3://$BUCKET/security-stack.yaml
aws s3 cp compute-stack.yaml   s3://$BUCKET/compute-stack.yaml
```

### Step 2 — Deploy (dev)

```bash
aws cloudformation create-stack \
  --stack-name main-infrastructure-dev \
  --template-body file://main-infrastructure.yaml \
  --parameters \
      ParameterKey=Environment,ParameterValue=dev \
      ParameterKey=TemplatesBucketName,ParameterValue=$BUCKET \
  --capabilities CAPABILITY_IAM \
  --on-failure ROLLBACK \
  --region $REGION
```

### Step 3 — Wait for completion

```bash
aws cloudformation wait stack-create-complete \
  --stack-name main-infrastructure-dev \
  --region $REGION

aws cloudformation describe-stacks \
  --stack-name main-infrastructure-dev \
  --query 'Stacks[0].Outputs' \
  --output table \
  --region $REGION
```

### Step 4 — Deploy (prod)

```bash
aws cloudformation create-stack \
  --stack-name main-infrastructure-prod \
  --template-body file://main-infrastructure.yaml \
  --parameters \
      ParameterKey=Environment,ParameterValue=prod \
      ParameterKey=TemplatesBucketName,ParameterValue=$BUCKET \
  --capabilities CAPABILITY_IAM \
  --on-failure ROLLBACK \
  --region $REGION
```

---

## Testing a Stack Update (change instance type)

The update below promotes the dev instance from `t2.micro` to `t2.small` by changing the environment parameter. Because the compute stack uses `!If [IsProd, t3.medium, t2.micro]`, a more targeted way is to directly edit `compute-stack.yaml`, re-upload, and then run an update:

```bash
# Re-upload the modified template
aws s3 cp compute-stack.yaml s3://$BUCKET/compute-stack.yaml

# Update the parent stack
aws cloudformation update-stack \
  --stack-name main-infrastructure-dev \
  --template-body file://main-infrastructure.yaml \
  --parameters \
      ParameterKey=Environment,ParameterValue=dev \
      ParameterKey=TemplatesBucketName,ParameterValue=$BUCKET \
  --capabilities CAPABILITY_IAM \
  --region $REGION

aws cloudformation wait stack-update-complete \
  --stack-name main-infrastructure-dev \
  --region $REGION
```

CloudFormation detects which nested stacks changed and only updates those, leaving the network and security stacks untouched.

---

## Rollback Configuration

The `--on-failure ROLLBACK` flag (passed at create time) is the primary rollback mechanism. If any resource creation fails, CloudFormation automatically deletes all resources it already created in that stack.

For update-time rollback, `--rollback-configuration` accepts CloudWatch alarm ARNs:

```bash
aws cloudformation update-stack \
  --stack-name main-infrastructure-dev \
  --template-body file://main-infrastructure.yaml \
  --parameters ... \
  --rollback-configuration "RollbackTriggers=[{Arn=arn:aws:cloudwatch:...:alarm:MyAlarm,Type=AWS::CloudWatch::Alarm}],MonitoringTimeInMinutes=5" \
  --capabilities CAPABILITY_IAM \
  --region $REGION
```

---

## Deliberate Failure + Rollback Test

`failure-test-stack.yaml` creates a VPC and subnet (which succeed), then tries to launch an EC2 instance with an intentionally invalid AMI (`ami-00000000000000000`). This triggers a stack failure and proves that CloudFormation rolls back the already-created resources.

```bash
# Deploy the deliberately broken stack
aws cloudformation create-stack \
  --stack-name rollback-test \
  --template-body file://failure-test-stack.yaml \
  --on-failure ROLLBACK \
  --region $REGION

# Watch events in real time
aws cloudformation describe-stack-events \
  --stack-name rollback-test \
  --query 'StackEvents[*].[ResourceStatus,ResourceType,ResourceStatusReason]' \
  --output table \
  --region $REGION
```

Expected event sequence:
1. `CREATE_IN_PROGRESS` → `RollbackTestVPC`
2. `CREATE_COMPLETE` → `RollbackTestVPC`
3. `CREATE_IN_PROGRESS` → `RollbackTestSubnet`
4. `CREATE_COMPLETE` → `RollbackTestSubnet`
5. `CREATE_IN_PROGRESS` → `FailingInstance`
6. `CREATE_FAILED` → `FailingInstance` *(invalid AMI)*
7. `DELETE_IN_PROGRESS` → `RollbackTestSubnet` *(rollback)*
8. `DELETE_IN_PROGRESS` → `RollbackTestVPC` *(rollback)*
9. `ROLLBACK_COMPLETE` → stack

---

## How Outputs Flow Between Stacks

```
NetworkStack
  └─ Outputs: VpcId, PublicSubnet1Id, PublicSubnet2Id
        │
        ├─▶ SecurityStack  (receives VpcId)
        │     └─ Outputs: WebServerSecurityGroupId
        │                          │
        └─▶ ComputeStack  ◀────────┘
              (receives PublicSubnet1Id, PublicSubnet2Id, WebServerSecurityGroupId)
```

The parent stack uses `!GetAtt NestedStack.Outputs.OutputKey` to extract values from each child and pass them as parameters to the next.

---

## Cleanup

```bash
# Delete in reverse order (or just delete the parent — it cascades)
aws cloudformation delete-stack --stack-name main-infrastructure-dev  --region $REGION
aws cloudformation delete-stack --stack-name main-infrastructure-prod --region $REGION
aws cloudformation delete-stack --stack-name rollback-test            --region $REGION

aws cloudformation wait stack-delete-complete --stack-name main-infrastructure-dev  --region $REGION
aws cloudformation wait stack-delete-complete --stack-name main-infrastructure-prod --region $REGION
```

---

## Success Criteria Checklist

| Requirement | How it is met |
|---|---|
| Nested stacks deploy in correct order | `DependsOn` on SecurityStack and ComputeStack resources in the parent |
| Outputs passed correctly between stacks | `!GetAtt NestedStack.Outputs.*` used for every cross-stack value |
| Stack updates without replacing everything | CloudFormation change-set logic only replaces resources whose properties changed |
| Rollback works on failure | `--on-failure ROLLBACK` + `failure-test-stack.yaml` demo |
| Dev: t2.micro, single instance | `!If [IsProd, t3.medium, t2.micro]` + `Condition: IsProd` on WebServer2 |
| Prod: t3.medium, multiple instances | Same condition — both instances and both subnets created in prod |
