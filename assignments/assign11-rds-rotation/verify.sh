#!/usr/bin/env bash
# verify.sh – manually trigger rotation and confirm the app Lambda still connects
# Run AFTER terraform apply completes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/terraform"

SECRET_ARN=$(terraform output -raw secret_arn)
APP_LAMBDA=$(terraform output -raw app_lambda_arn | awk -F: '{print $NF}')   # function name
APP_FN_NAME=$(terraform output -raw app_lambda_arn | sed 's/.*function://' | cut -d: -f1)

echo "========================================"
echo " Secret ARN  : $SECRET_ARN"
echo " App function: $APP_FN_NAME"
echo "========================================"

# ── 1. Test connection BEFORE rotation ───────────────────────────────────────
echo ""
echo ">>> [1/4] Invoking app Lambda BEFORE rotation..."
aws lambda invoke \
  --function-name "$APP_FN_NAME" \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/before_rotation.json
echo "Response:"
cat /tmp/before_rotation.json
echo ""

# ── 2. Trigger manual rotation ───────────────────────────────────────────────
echo ">>> [2/4] Triggering manual rotation..."
aws secretsmanager rotate-secret --secret-id "$SECRET_ARN"
echo "    Rotation triggered. Waiting 90 seconds for Lambda to complete..."
sleep 90

# ── 3. Check rotation status ─────────────────────────────────────────────────
echo ">>> [3/4] Checking rotation status..."
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ARN" \
  --query '{LastRotatedDate:LastRotatedDate, RotationEnabled:RotationEnabled}' \
  --output table

# ── 4. Test connection AFTER rotation ────────────────────────────────────────
echo ""
echo ">>> [4/4] Invoking app Lambda AFTER rotation..."
aws lambda invoke \
  --function-name "$APP_FN_NAME" \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/after_rotation.json
echo "Response:"
cat /tmp/after_rotation.json
echo ""

# ── 5. CloudWatch log check ──────────────────────────────────────────────────
echo ">>> CloudWatch – last 20 rotation log events:"
LOG_GROUP="/aws/lambda/$(terraform output -raw rotation_lambda_arn | sed 's/.*function://' | cut -d: -f1)"
aws logs tail "$LOG_GROUP" --since 10m 2>/dev/null || echo "(No log events yet – check Console)"

echo ""
echo "========================================"
echo " Verification complete."
echo "========================================"
