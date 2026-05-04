# Deployment Information

## Deployment Date
2026-02-02

## Stack Details
- **Stack Name**: chikwex-order-processing-system
- **Region**: us-east-1
- **Account ID**: 866934333672
- **User**: Chikwe

## API Endpoint
```
https://k295kgtlkg.execute-api.us-east-1.amazonaws.com/prod
```

## Resource Outputs

### API Gateway
- **Endpoint URL**: https://k295kgtlkg.execute-api.us-east-1.amazonaws.com/prod
- **API ID**: k295kgtlkg
- **Stage**: prod

### DynamoDB
- **Table Name**: chikwex-order-processing-system-orders
- **Primary Key**: orderId (HASH), createdAt (RANGE)
- **GSI**: status-index

### SQS Queues
- **Processing Queue**: https://sqs.us-east-1.amazonaws.com/866934333672/chikwex-order-processing-system-order-processing-queue
- **Dead Letter Queue**: https://sqs.us-east-1.amazonaws.com/866934333672/chikwex-order-processing-system-order-processing-dlq

### SNS Topic
- **Topic ARN**: arn:aws:sns:us-east-1:866934333672:chikwex-order-processing-system-order-notifications

### Step Functions
- **State Machine ARN**: arn:aws:states:us-east-1:866934333672:stateMachine:chikwex-order-processing-system-order-workflow

### Lambda Functions
1. **Order Creation**: chikwex-order-processing-system-OrderCreationFunction-xxxxx
2. **Order Retrieval**: chikwex-order-processing-system-OrderRetrievalFunction-xxxxx
3. **Order Processing**: chikwex-order-processing-system-OrderProcessingFunction-xxxxx
4. **Order Notification**: chikwex-order-processing-system-OrderNotificationFunction-xxxxx

## Next Steps

### 1. Get API Key

Run this command to get your API key:

```bash
python -m awscli apigateway get-api-keys --include-values
```

Or get it from AWS Console:
1. Go to: https://console.aws.amazon.com/apigateway/
2. Click on `chikwex-order-processing-system-orders-api`
3. Left sidebar → **API Keys**
4. You should see an auto-generated key
5. Click on it and then click **Show** to reveal the key value

### 2. Test the API

Once you have the API key, set it as an environment variable:

```bash
export API_ENDPOINT="https://k295kgtlkg.execute-api.us-east-1.amazonaws.com/prod"
export API_KEY="your-api-key-here"
```

Then test:

```bash
# Create an order
curl -X POST "${API_ENDPOINT}/orders" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{
    "customerId": "CUST-001",
    "customerEmail": "you@example.com",
    "items": [
      {"productId": "PROD-001", "quantity": 2, "price": 29.99}
    ]
  }'
```

### 3. Monitor Your Application

**CloudWatch Logs:**
- https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups

**X-Ray Service Map:**
- https://console.aws.amazon.com/xray/home?region=us-east-1#/service-map

**DynamoDB Table:**
- https://console.aws.amazon.com/dynamodbv2/home?region=us-east-1#table?name=chikwex-order-processing-system-orders

**Step Functions:**
- https://console.aws.amazon.com/states/home?region=us-east-1#/statemachines

## Cost Monitoring

All resources are within AWS Free Tier for testing purposes. Estimated cost for light usage: <$1/month

## Clean Up

When you're done, delete everything with:

```bash
cd ChikwexServerlessAssign3
sam delete
```

This will remove all resources and stop any charges.
