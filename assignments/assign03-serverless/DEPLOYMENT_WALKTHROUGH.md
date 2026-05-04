# Deployment Walkthrough - Learning Guide

This guide walks you through deploying your serverless application step-by-step with explanations.

## Phase 1: Pre-Deployment Understanding

### What is AWS SAM?

**SAM (Serverless Application Model)** is a framework that:
- Simplifies serverless application deployment
- Extends AWS CloudFormation
- Provides shorthand syntax for Lambda, API Gateway, DynamoDB, etc.
- Includes CLI tools for local testing and deployment

### What Happens During Deployment?

```
Your Code → SAM Build → S3 Upload → CloudFormation → AWS Resources
```

1. **SAM Build**: Packages your Lambda code and dependencies
2. **S3 Upload**: Uploads packages to S3 bucket
3. **CloudFormation**: Creates/updates infrastructure
4. **AWS Resources**: Lambda functions, API Gateway, DynamoDB, etc. are created

## Phase 2: AWS CLI Configuration

### Understanding AWS Credentials

**Access Key ID**: Think of this as your username (can be public)
**Secret Access Key**: Think of this as your password (keep secret!)

These credentials allow AWS CLI to make API calls on your behalf.

### Configuration Files Created

When you run `aws configure`, it creates two files:

**~/.aws/credentials**
```ini
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
```

**~/.aws/config**
```ini
[default]
region = us-east-1
output = json
```

### Why Region Matters

- **Latency**: Choose region closest to your users
- **Cost**: Pricing varies by region
- **Compliance**: Some data must stay in specific regions
- **Services**: Not all services available in all regions

**Popular Regions:**
- `us-east-1`: US East (N. Virginia) - Most services, cheapest
- `us-west-2`: US West (Oregon) - West coast
- `eu-west-1`: Europe (Ireland) - GDPR compliance
- `ap-southeast-1`: Asia Pacific (Singapore) - Asian users

## Phase 3: SAM Build

### What `sam build` Does

```bash
sam build
```

**Step-by-step:**
1. Reads `template.yaml`
2. Finds all Lambda functions (CodeUri paths)
3. For each function:
   - Creates temporary build directory
   - Copies function code
   - Installs dependencies from `requirements.txt`
   - Creates deployment package (ZIP)
4. Outputs to `.aws-sam/build/` directory

**Example Output:**
```
Building codeuri: src/lambdas/order-creation runtime: python3.11
Running PythonPipBuilder:ResolveDependencies
Running PythonPipBuilder:CopySource

Build Succeeded

Built Artifacts: .aws-sam/build
```

### Understanding Lambda Deployment Packages

Each Lambda function needs:
- **Code**: Your Python files (app.py)
- **Dependencies**: Libraries from requirements.txt (boto3, aws-xray-sdk)
- **Size Limit**: 50 MB zipped, 250 MB unzipped

SAM automatically handles this packaging.

## Phase 4: SAM Deploy

### What `sam deploy --guided` Does

**Guided mode prompts you for:**

1. **Stack Name**: Name for your CloudFormation stack
   - Example: `chikwex-order-system`
   - Must be unique in your AWS account + region

2. **AWS Region**: Where to deploy
   - Example: `us-east-1`

3. **Confirm changes**: Review changes before deployment
   - Shows what will be created/updated/deleted

4. **Allow SAM CLI IAM role creation**:
   - SAM needs to create IAM roles for Lambda functions
   - These give Lambda permissions to access DynamoDB, SQS, etc.

5. **Save arguments to samconfig.toml**:
   - Saves your choices for next deployment
   - Next time you can just run `sam deploy` (no --guided)

### CloudFormation Change Sets

Before making changes, CloudFormation shows you:
```
-----------------------------------------
CloudFormation stack changeset
-----------------------------------------
Operation    LogicalResourceId        ResourceType
-----------------------------------------
+ Add        OrdersTable              AWS::DynamoDB::Table
+ Add        OrderCreationFunction    AWS::Lambda::Function
+ Add        OrdersApi                AWS::ApiGateway::RestApi
...
```

**Operations:**
- `+ Add`: New resource will be created
- `* Modify`: Existing resource will be updated
- `- Remove`: Resource will be deleted

### Deployment Timeline

**What happens during deployment:**

```
[0:00] Upload artifacts to S3
[0:30] Create CloudFormation stack
[1:00] Create DynamoDB table
[1:30] Create SQS queues
[2:00] Create SNS topics
[3:00] Create Lambda functions
[4:00] Create API Gateway
[4:30] Create IAM roles and policies
[5:00] Create Step Functions state machine
[5:30] Create CloudWatch log groups and alarms
[6:00] ✅ Stack creation complete
```

**Total time: ~5-10 minutes** (first deployment)

## Phase 5: Understanding Stack Outputs

After deployment, you'll see **Outputs**:

```
-----------------------------------------
Outputs
-----------------------------------------
Key: ApiEndpoint
Value: https://abc123.execute-api.us-east-1.amazonaws.com/prod
Description: API Gateway endpoint URL

Key: OrdersTableName
Value: chikwex-order-system-orders
Description: DynamoDB table name
```

**Why Outputs Matter:**
- **ApiEndpoint**: This is your REST API URL
- **Table Names**: Use for direct database queries
- **ARNs**: Amazon Resource Names for accessing resources

**Save these outputs!** You'll need them for testing.

## Phase 6: Getting API Key

After deployment, you need an API key to call the API.

### Via AWS Console:

1. Go to: https://console.aws.amazon.com/apigateway/
2. Click on your API (e.g., `chikwex-order-system-orders-api`)
3. Left sidebar → **API Keys**
4. Click **Create API Key**
5. Name: `test-key`
6. Click **Save**
7. Click **Show** to reveal the key
8. **Copy the API key value**

### Associate with Usage Plan:

1. Still in API Gateway console
2. Left sidebar → **Usage Plans**
3. Click on your usage plan
4. Click **Add API Key to Usage Plan**
5. Select your API key
6. Click **✓** (checkmark)

**Now your API key is active!**

### Via AWS CLI (Alternative):

```bash
# List API IDs
python -m awscli apigateway get-rest-apis

# Create API key
python -m awscli apigateway create-api-key \
  --name test-key \
  --enabled

# Note the API key ID from output, then associate with usage plan
# (Usage plan ID is in CloudFormation outputs)
```

## Phase 7: Testing Your Deployed API

### Test 1: Create an Order

```bash
# Set environment variables
export API_ENDPOINT="https://YOUR-API-ID.execute-api.us-east-1.amazonaws.com/prod"
export API_KEY="your-api-key-here"

# Create order
curl -X POST "${API_ENDPOINT}/orders" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{
    "customerId": "CUST-001",
    "customerEmail": "you@example.com",
    "items": [
      {
        "productId": "PROD-001",
        "quantity": 2,
        "price": 29.99
      }
    ],
    "shippingAddress": {
      "street": "123 Test St",
      "city": "Test City",
      "state": "TC",
      "zipCode": "12345",
      "country": "USA"
    }
  }'
```

**What happens behind the scenes:**

1. **API Gateway** receives request
2. **Checks API key** authentication
3. **Validates** request format
4. **Invokes** Order Creation Lambda
5. **Lambda**:
   - Validates order data
   - Generates unique order ID
   - Calculates total ($59.98)
   - Saves to DynamoDB
   - Sends message to SQS
   - Publishes CloudWatch metric
   - Returns response
6. **API Gateway** returns response to you

**Expected Response:**
```json
{
  "message": "Order created successfully",
  "orderId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "PENDING",
  "totalAmount": 59.98,
  "createdAt": "2024-01-15T10:30:00Z"
}
```

### Test 2: Get Order by ID

```bash
# Use the orderId from previous response
ORDER_ID="550e8400-e29b-41d4-a716-446655440000"

curl -X GET "${API_ENDPOINT}/orders/${ORDER_ID}" \
  -H "X-API-Key: ${API_KEY}"
```

### Test 3: List All Orders

```bash
curl -X GET "${API_ENDPOINT}/orders" \
  -H "X-API-Key: ${API_KEY}"
```

## Phase 8: Monitoring Your Application

### CloudWatch Logs

**View Lambda execution logs:**

```bash
# List log groups
python -m awscli logs describe-log-groups \
  --log-group-name-prefix '/aws/lambda/chikwex'

# Tail logs in real-time
python -m awscli logs tail \
  /aws/lambda/your-stack-name-OrderCreationFunction-xyz123 \
  --follow
```

**What you'll see:**
- `START RequestId: abc123` - Lambda starts
- Your print statements
- `END RequestId: abc123` - Lambda completes
- `REPORT Duration: 150ms Memory Used: 80MB` - Metrics

### CloudWatch Metrics

**Via Console:**
1. Go to: https://console.aws.amazon.com/cloudwatch/
2. Left sidebar → **Metrics** → **All metrics**
3. Browse:
   - **AWS/Lambda**: Function invocations, errors, duration
   - **AWS/DynamoDB**: Read/write capacity
   - **OrderProcessingSystem**: Your custom metrics!

**View Custom Metrics:**
- OrdersCreated
- OrderValue
- PaymentsProcessed
- NotificationsSent

### X-Ray Traces

**Via Console:**
1. Go to: https://console.aws.amazon.com/xray/
2. Click **Service map**
3. See visual representation:
   ```
   Client → API Gateway → Lambda → DynamoDB
                     └→ SQS
   ```
4. Click on any node to see details
5. Click **Traces** to see individual requests

**What X-Ray Shows:**
- Request duration (end-to-end latency)
- Where time is spent (Lambda vs DynamoDB)
- Errors and exceptions
- Service dependencies

### SQS Queue Monitoring

**Check queue status:**

```bash
# List queues
python -m awscli sqs list-queues

# Get queue attributes
python -m awscli sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/123/your-queue \
  --attribute-names All
```

**Key metrics:**
- `ApproximateNumberOfMessages`: Messages waiting to be processed
- `ApproximateNumberOfMessagesNotVisible`: Messages being processed
- `ApproximateNumberOfMessagesDelayed`: Delayed messages

### DynamoDB Table Monitoring

**Via Console:**
1. Go to: https://console.aws.amazon.com/dynamodb/
2. Click **Tables**
3. Click on your table (e.g., `chikwex-order-system-orders`)
4. Click **Monitor** tab

**What to look for:**
- Read/write capacity consumed
- Throttled requests (should be 0)
- User errors (should be low)

## Phase 9: Understanding Costs

### AWS Free Tier (First 12 Months)

**Lambda:**
- 1M requests/month free
- 400,000 GB-seconds compute time free

**API Gateway:**
- 1M API calls/month free (first 12 months)

**DynamoDB:**
- 25 GB storage free (forever)
- 25 read/write capacity units free (forever)

**SQS:**
- 1M requests/month free (forever)

**SNS:**
- 1M publishes/month free (forever)

**CloudWatch:**
- 10 custom metrics free
- 5 GB log ingestion free
- 1M API requests free

**For this project:**
- **Testing (100 orders)**: $0.00 (within free tier)
- **Light usage (1,000 orders/month)**: ~$0.50/month
- **Production (10,000 orders/month)**: ~$6/month

### Cost Monitoring

**Set up billing alerts:**

```bash
# Enable billing alerts (one-time)
python -m awscli cloudwatch put-metric-alarm \
  --alarm-name billing-alarm-10-dollars \
  --alarm-description "Alert when charges exceed $10" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1
```

## Phase 10: Troubleshooting Common Issues

### Issue: API Returns 403 Forbidden

**Cause**: Missing or invalid API key

**Fix:**
1. Verify API key is in request header: `X-API-Key: your-key`
2. Check API key is associated with usage plan
3. Create new API key if needed

### Issue: Lambda Timeout

**Cause**: Function takes longer than configured timeout (30s default)

**Fix:**
1. Check CloudWatch Logs for what's slow
2. Optimize code or increase timeout in template.yaml

### Issue: DynamoDB Item Not Found

**Cause**: Order ID doesn't exist or incorrect

**Fix:**
1. Verify order was created (check CloudWatch Logs)
2. Ensure using correct order ID (UUID format)
3. Check DynamoDB table directly in console

### Issue: SQS Messages Not Processing

**Cause**: Lambda not triggered or failing

**Fix:**
1. Check Lambda event source mapping
2. View DLQ for failed messages
3. Check IAM permissions

### Issue: Deployment Failed

**Cause**: Various (permissions, resource limits, etc.)

**Fix:**
1. Read error message carefully
2. Check CloudFormation Events in console
3. Common fixes:
   - Stack name already exists: Use different name
   - IAM permissions: Ensure your AWS account has admin access
   - Resource limits: Check AWS service quotas

## Next Steps After Deployment

1. **Test all endpoints** thoroughly
2. **Monitor CloudWatch Logs** to see your code running
3. **Check X-Ray traces** to understand performance
4. **Experiment with failures**:
   - Send invalid data to test validation
   - Check DLQ for failed messages
5. **Modify Lambda code** and redeploy:
   ```bash
   sam build
   sam deploy  # No --guided needed after first time
   ```
6. **Scale test**: Create 100 orders and watch auto-scaling
7. **Add features**: Implement new functionality

## Clean Up (When Done)

To delete everything and stop charges:

```bash
sam delete

# Or manually
python -m awscli cloudformation delete-stack \
  --stack-name chikwex-order-system
```

**This deletes:**
- All Lambda functions
- API Gateway
- DynamoDB table (and all data!)
- SQS queues
- SNS topics
- All other resources

---

## Congratulations! 🎉

You've successfully deployed a production-grade serverless application!

You now understand:
- ✅ How AWS authentication works
- ✅ How to package serverless applications
- ✅ How Infrastructure as Code works
- ✅ How to deploy to the cloud
- ✅ How to test live APIs
- ✅ How to monitor applications in production
- ✅ How serverless architecture scales
- ✅ How to debug cloud applications

**This knowledge applies to real-world production systems!**
