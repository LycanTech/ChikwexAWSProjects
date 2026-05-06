# Assignment 11 — RDS Secret Rotation with Lambda

## Overview

Automatic RDS MySQL password rotation using AWS Secrets Manager and a custom Lambda rotation function. The rotation Lambda implements the four-step Secrets Manager protocol, creates a new DB user, verifies the connection, then promotes the new credentials and removes the old user — all without application downtime.

- **Rotation schedule**: every 7 days
- **Rotation time**: < 2 minutes
- **Prefix**: `chikwex`
- **Region**: `us-east-1`

---

## Architecture

```
                ┌─────────────────────────────────────────┐
                │             Default VPC                  │
                │                                         │
                │  ┌─────────────────┐                   │
                │  │  Secrets Manager │◄──── App Lambda   │
                │  │  (7-day rotate) │      (reads secret)│
                │  └────────┬────────┘                   │
                │           │ triggers                    │
                │  ┌────────▼────────┐                   │
                │  │ Rotation Lambda  │                   │
                │  │  (4-step proto) │                   │
                │  └────────┬────────┘                   │
                │           │ MySQL :3306                 │
                │  ┌────────▼────────┐                   │
                │  │   RDS MySQL     │                   │
                │  │  (db.t3.micro)  │                   │
                │  └─────────────────┘                   │
                └─────────────────────────────────────────┘
```

---

## How rotation works

The rotation Lambda (`lambda/rotation/rotation.py`) implements the Secrets Manager four-step protocol:

| Step | Action |
| --- | --- |
| `createSecret` | Generate a new random password and store it as `AWSPENDING` version |
| `setSecret` | Create a new MySQL user with the new password |
| `testSecret` | Verify a connection to RDS succeeds with the new credentials |
| `finishSecret` | Promote `AWSPENDING` to `AWSCURRENT`, delete the old MySQL user |

If any step fails, the rotation aborts and the existing credentials remain valid — no downtime.

---

## Project Structure

```
├── terraform/
│   ├── main.tf        # VPC, RDS, Secrets Manager, Lambda functions, IAM
│   ├── variables.tf   # region, prefix, db_name, master credentials
│   └── outputs.tf     # RDS endpoint, secret ARN, Lambda names
├── lambda/
│   ├── rotation/
│   │   ├── rotation.py        # Rotation Lambda (4-step protocol)
│   │   └── requirements.txt   # pymysql
│   └── app/
│       ├── app.py             # App Lambda — reads secret, connects to RDS
│       └── requirements.txt   # pymysql, boto3
├── deploy.sh          # Package and deploy Lambda ZIPs
└── verify.sh          # Test connection + trigger manual rotation
```

---

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured (`us-east-1`)
- Python 3.11+ (for packaging Lambda layers)

---

## Deployment

### 1. Package Lambda functions

```bash
bash deploy.sh
```

This installs Python dependencies and creates ZIP packages for both Lambdas.

### 2. Deploy infrastructure

```bash
cd terraform
terraform init
terraform apply -var="db_master_password=YourInitialPassword!" -auto-approve
```

### 3. Note the outputs

```bash
terraform output
# rds_endpoint, secret_arn, rotation_lambda_name, app_lambda_name
```

---

## Testing Rotation

### Trigger manual rotation

```bash
SECRET_ARN=$(terraform -chdir=terraform output -raw secret_arn)

aws secretsmanager rotate-secret \
  --secret-id "$SECRET_ARN" \
  --region us-east-1
```

### Verify the app Lambda can still connect after rotation

```bash
APP_LAMBDA=$(terraform -chdir=terraform output -raw app_lambda_name)

aws lambda invoke \
  --function-name "$APP_LAMBDA" \
  --region us-east-1 \
  response.json

cat response.json
```

### Check rotation CloudWatch logs

```bash
aws logs tail /aws/lambda/chikwex-rotation --follow --region us-east-1
```

Or run the full verification script:

```bash
bash verify.sh
```

---

## Success Criteria

- Rotation completes without errors in CloudWatch logs
- App Lambda connects successfully after rotation (old credentials no longer accepted)
- Rotation completes in < 2 minutes
- Old DB user is deleted after `finishSecret` step

---

## Cleanup

```bash
terraform destroy -auto-approve
```
