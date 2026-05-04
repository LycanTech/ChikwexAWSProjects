#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Step 1: Create Orders table with DynamoDB Streams ==="
aws dynamodb create-table \
  --table-name Orders \
  --attribute-definitions \
      AttributeName=orderId,AttributeType=S \
      AttributeName=status,AttributeType=S \
  --key-schema \
      AttributeName=orderId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
  --global-secondary-indexes '[
    {
      "IndexName": "status-index",
      "KeySchema": [{"AttributeName":"status","KeyType":"HASH"}],
      "Projection": {"ProjectionType":"ALL"}
    }
  ]' \
  --region "$REGION"

echo "Waiting for Orders table to become ACTIVE..."
aws dynamodb wait table-exists --table-name Orders --region "$REGION"

echo "=== Step 2: Enable TTL on Orders table ==="
aws dynamodb update-time-to-live \
  --table-name Orders \
  --time-to-live-specification "Enabled=true,AttributeName=expiresAt" \
  --region "$REGION"

echo "=== Step 3: Create CustomerStats table ==="
aws dynamodb create-table \
  --table-name CustomerStats \
  --attribute-definitions AttributeName=customerId,AttributeType=S \
  --key-schema AttributeName=customerId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo "Waiting for CustomerStats table to become ACTIVE..."
aws dynamodb wait table-exists --table-name CustomerStats --region "$REGION"

echo "=== Step 4: Create IAM role for Lambda ==="
ROLE_NAME="assign13-lambda-role"

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

echo "Waiting 10s for IAM role to propagate..."
sleep 10

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "=== Step 5: Package and deploy OrderAggregator Lambda ==="
zip order_aggregator.zip order_aggregator.py

aws lambda create-function \
  --function-name OrderAggregator \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler order_aggregator.lambda_handler \
  --zip-file fileb://order_aggregator.zip \
  --region "$REGION"

echo "=== Step 6: Package and deploy OrderSeeder Lambda ==="
zip order_seeder.zip order_seeder.py

aws lambda create-function \
  --function-name OrderSeeder \
  --runtime python3.12 \
  --role "$ROLE_ARN" \
  --handler order_seeder.lambda_handler \
  --zip-file fileb://order_seeder.zip \
  --timeout 30 \
  --region "$REGION"

echo "=== Step 7: Connect DynamoDB Stream to OrderAggregator ==="
STREAM_ARN=$(aws dynamodb describe-table \
  --table-name Orders \
  --query "Table.LatestStreamArn" \
  --output text \
  --region "$REGION")

echo "Stream ARN: $STREAM_ARN"

aws lambda create-event-source-mapping \
  --function-name OrderAggregator \
  --event-source-arn "$STREAM_ARN" \
  --batch-size 100 \
  --starting-position LATEST \
  --region "$REGION"

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Invoke seeder:  aws lambda invoke --function-name OrderSeeder --region $REGION out.json"
echo "  2. Watch stats:    aws dynamodb scan --table-name CustomerStats --region $REGION"
echo "  3. Query by status: aws dynamodb query --table-name Orders --index-name status-index \\"
echo "       --key-condition-expression '#s = :s' \\"
echo "       --expression-attribute-names '{\"#s\":\"status\"}' \\"
echo "       --expression-attribute-values '{\":s\":{\"S\":\"COMPLETE\"}}' \\"
echo "       --region $REGION"
