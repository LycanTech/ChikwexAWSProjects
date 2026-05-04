# Serverless Order Processing System

A fully serverless e-commerce order processing system built on AWS using Lambda, API Gateway, DynamoDB, SQS, SNS, EventBridge, and Step Functions.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Installation](#installation)
- [Deployment](#deployment)
- [API Documentation](#api-documentation)
- [Testing](#testing)
- [Monitoring & Observability](#monitoring--observability)
- [Cost Estimation](#cost-estimation)
- [Troubleshooting](#troubleshooting)
- [Clean Up](#clean-up)

## Overview

This project implements a serverless order processing system for an e-commerce platform. The system handles order creation, processing, inventory management, payment processing (simulated), and customer notifications using AWS serverless services.

**Key Capabilities:**
- REST API for order management (create, retrieve, list)
- Asynchronous order processing with SQS
- Fan-out notifications using SNS
- Complex workflow orchestration with Step Functions
- Comprehensive observability with X-Ray and CloudWatch
- Error handling with Dead Letter Queues and retry logic

## Architecture

The system uses a microservices architecture with the following components:

- **API Gateway**: REST API with API key authentication and CORS
- **Lambda Functions**: Serverless compute for business logic
  - Order Creation
  - Order Retrieval
  - Order Processing
  - Order Notification
- **DynamoDB**: NoSQL database with GSI for status-based queries
- **SQS**: Message queue for async processing with DLQ
- **SNS**: Pub/sub for notifications
- **Step Functions**: Workflow orchestration
- **X-Ray & CloudWatch**: Observability and monitoring

For detailed architecture diagrams and event flows, see [docs/architecture.md](docs/architecture.md).

## Features

### API Layer
- ✅ REST API with API Gateway
- ✅ Endpoints: POST /orders, GET /orders/{id}, GET /orders
- ✅ Request validation and API key authentication
- ✅ CORS enabled
- ✅ OpenAPI/Swagger specification

### Business Logic
- ✅ Order creation with validation
- ✅ Order processing (inventory check, payment processing)
- ✅ Order notifications (email/SMS simulation)
- ✅ Proper error handling and retries
- ✅ Compensating transactions for failures

### Data Layer
- ✅ DynamoDB table with partition key (orderId) and sort key (createdAt)
- ✅ DynamoDB Streams enabled
- ✅ Global Secondary Index (GSI) for status-based queries

### Asynchronous Processing
- ✅ SQS queue for order processing
- ✅ Dead Letter Queue (DLQ) for failed messages
- ✅ SNS topic for fan-out notifications

### Orchestration
- ✅ Step Functions state machine for order workflow
- ✅ Retry logic with exponential backoff
- ✅ Compensating transactions (payment refunds)

### Observability
- ✅ X-Ray tracing for all Lambda functions
- ✅ CloudWatch Logs with 7-day retention
- ✅ Custom CloudWatch metrics
- ✅ CloudWatch Alarms for error detection

## Prerequisites

Before deploying this project, ensure you have:

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
   ```bash
   aws --version
   aws configure
   ```
3. **AWS SAM CLI** installed
   ```bash
   sam --version
   ```
   Install: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html

4. **Python 3.11** or later
   ```bash
   python --version
   ```

5. **Git** (optional, for version control)

## Project Structure

```
ChikwexServerlessAssign3/
├── template.yaml                          # SAM template (main IaC file)
├── README.md                              # This file
├── src/
│   └── lambdas/
│       ├── order-creation/
│       │   ├── app.py                     # Order creation Lambda
│       │   └── requirements.txt           # Python dependencies
│       ├── order-retrieval/
│       │   ├── app.py                     # Order retrieval Lambda
│       │   └── requirements.txt
│       ├── order-processing/
│       │   ├── app.py                     # Order processing Lambda
│       │   └── requirements.txt
│       └── order-notification/
│           ├── app.py                     # Notification Lambda
│           └── requirements.txt
├── infrastructure/
│   └── order-workflow.asl.json            # Step Functions state machine definition
├── docs/
│   ├── architecture.md                    # Architecture documentation
│   └── api-specification.yaml             # OpenAPI/Swagger spec
└── tests/
    └── (test files - to be added)
```

## Installation

### 1. Clone or Download the Project

```bash
cd ChikwexServerlessAssign3
```

### 2. Install Python Dependencies (Optional for Local Testing)

```bash
# Create virtual environment
python -m venv venv

# Activate virtual environment
# On Windows:
venv\Scripts\activate
# On macOS/Linux:
source venv/bin/activate

# Install dependencies
pip install boto3 aws-xray-sdk
```

## Deployment

### Option 1: Guided Deployment (Recommended for First Time)

```bash
sam build
sam deploy --guided
```

You'll be prompted for:
- **Stack Name**: e.g., `chikwex-order-processing-system`
- **AWS Region**: e.g., `us-east-1`
- **Confirm changes**: Y
- **Allow SAM CLI IAM role creation**: Y
- **Save arguments to configuration**: Y

### Option 2: Direct Deployment (After Initial Setup)

```bash
# Build the application
sam build

# Deploy to AWS
sam deploy
```

### Deployment Steps Explained

1. **Build**: SAM packages your Lambda functions and dependencies
2. **Package**: SAM uploads artifacts to S3
3. **Deploy**: SAM creates/updates CloudFormation stack with all resources

**Deployment Time**: ~5-10 minutes for initial deployment

### Post-Deployment

After successful deployment, SAM will output:
- **API Endpoint URL**: Your API Gateway endpoint
- **Orders Table Name**: DynamoDB table name
- **Queue URLs**: SQS queue and DLQ URLs
- **Topic ARN**: SNS topic ARN
- **State Machine ARN**: Step Functions ARN

**Save these values** - you'll need them for testing!

Example output:
```
Outputs
-----------------------------------------------
ApiEndpoint: https://abc123.execute-api.us-east-1.amazonaws.com/prod
OrdersTableName: chikwex-order-processing-system-orders
OrderQueueURL: https://sqs.us-east-1.amazonaws.com/123456789/order-queue
```

## API Documentation

### Authentication

All API requests require an API key. After deployment:

1. Get the API key from AWS Console:
   - Go to API Gateway → APIs → Your API → API Keys
   - Create a new API key or use the auto-generated one
   - Associate it with the usage plan

2. Include the API key in request headers:
   ```
   X-API-Key: your-api-key-here
   ```

### API Endpoints

#### 1. Create Order

**POST** `/orders`

Creates a new order and submits it for processing.

**Request Body:**
```json
{
  "customerId": "CUST-12345",
  "customerEmail": "customer@example.com",
  "items": [
    {
      "productId": "PROD-001",
      "quantity": 2,
      "price": 29.99
    },
    {
      "productId": "PROD-002",
      "quantity": 1,
      "price": 49.99
    }
  ],
  "shippingAddress": {
    "street": "123 Main St",
    "city": "New York",
    "state": "NY",
    "zipCode": "10001",
    "country": "USA"
  }
}
```

**Response (201 Created):**
```json
{
  "message": "Order created successfully",
  "orderId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "PENDING",
  "totalAmount": 109.97,
  "createdAt": "2024-01-15T10:30:00Z"
}
```

#### 2. Get Order by ID

**GET** `/orders/{orderId}`

Retrieves detailed information about a specific order.

**Response (200 OK):**
```json
{
  "orderId": "550e8400-e29b-41d4-a716-446655440000",
  "createdAt": "2024-01-15T10:30:00Z",
  "customerId": "CUST-12345",
  "customerEmail": "customer@example.com",
  "items": [...],
  "totalAmount": 109.97,
  "status": "PENDING",
  "updatedAt": "2024-01-15T10:30:00Z"
}
```

#### 3. List Orders

**GET** `/orders?status=PENDING&limit=20`

Lists orders with optional filtering.

**Query Parameters:**
- `status` (optional): PENDING, PROCESSING, COMPLETED, or FAILED
- `limit` (optional): Number of orders to return (max 100, default 50)

**Response (200 OK):**
```json
{
  "orders": [...],
  "count": 2,
  "filter": {
    "status": "PENDING"
  }
}
```

For complete API documentation, see [docs/api-specification.yaml](docs/api-specification.yaml).

## Testing

### Manual Testing with cURL

#### 1. Create an Order

```bash
# Replace with your API endpoint and API key
export API_ENDPOINT="https://abc123.execute-api.us-east-1.amazonaws.com/prod"
export API_KEY="your-api-key-here"

curl -X POST "${API_ENDPOINT}/orders" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{
    "customerId": "CUST-12345",
    "customerEmail": "test@example.com",
    "items": [
      {
        "productId": "PROD-001",
        "quantity": 2,
        "price": 29.99
      }
    ]
  }'
```

#### 2. Get Order by ID

```bash
# Replace ORDER_ID with the ID from the create response
export ORDER_ID="550e8400-e29b-41d4-a716-446655440000"

curl -X GET "${API_ENDPOINT}/orders/${ORDER_ID}" \
  -H "X-API-Key: ${API_KEY}"
```

#### 3. List All Orders

```bash
curl -X GET "${API_ENDPOINT}/orders" \
  -H "X-API-Key: ${API_KEY}"
```

#### 4. List Orders by Status

```bash
curl -X GET "${API_ENDPOINT}/orders?status=PENDING&limit=10" \
  -H "X-API-Key: ${API_KEY}"
```

### Testing with Postman

1. **Import the OpenAPI spec**: Import `docs/api-specification.yaml` into Postman
2. **Configure environment variables**:
   - `base_url`: Your API endpoint
   - `api_key`: Your API key
3. **Run the collection**: Execute all requests

### Testing Step Functions

Manually trigger the Step Functions workflow:

```bash
# Get the State Machine ARN from deployment outputs
export STATE_MACHINE_ARN="arn:aws:states:us-east-1:123456789:stateMachine:order-workflow"

# Start execution
aws stepfunctions start-execution \
  --state-machine-arn "${STATE_MACHINE_ARN}" \
  --input '{
    "orderId": "test-order-123",
    "createdAt": "2024-01-15T10:30:00Z"
  }'
```

View execution in AWS Console → Step Functions → State machines → Your state machine

### Expected Test Results

✅ **Order Creation**:
- Returns 201 status with order details
- Order appears in DynamoDB
- Message sent to SQS queue
- CloudWatch metrics published

✅ **Order Retrieval**:
- Returns 200 with correct order data
- Handles non-existent orders with 404

✅ **Order Processing**:
- SQS triggers Lambda
- Order status updated to PROCESSING
- SNS notification published

✅ **Notifications**:
- Lambda logs show email/SMS notifications
- CloudWatch metrics show notification count

## Monitoring & Observability

### CloudWatch Logs

View Lambda logs:
```bash
# Order Creation logs
aws logs tail /aws/lambda/order-creation --follow

# Order Processing logs
aws logs tail /aws/lambda/order-processing --follow
```

### X-Ray Traces

1. Open AWS Console → X-Ray → Service map
2. View service dependencies and latency
3. Analyze traces for slow requests

### CloudWatch Metrics

Custom metrics published:
- `OrdersCreated`: Count of orders created
- `OrderValue`: Total order values
- `OrdersProcessed`: Count of processed orders
- `PaymentsProcessed`: Payment processing results
- `NotificationsSent`: Notification delivery status

View metrics:
```bash
aws cloudwatch get-metric-statistics \
  --namespace OrderProcessingSystem \
  --metric-name OrdersCreated \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-16T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### CloudWatch Alarms

Monitor these alarms:
- **Order Processing Errors**: Triggers when error rate > 10
- **DLQ Messages**: Triggers when messages land in DLQ

View alarms:
```bash
aws cloudwatch describe-alarms
```

### Log Insights Queries

Sample queries:

**Find all errors:**
```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
```

**Order processing duration:**
```
fields @timestamp, @duration
| filter @type = "REPORT"
| stats avg(@duration), max(@duration), min(@duration)
```

## Cost Estimation

Based on 10,000 orders per month:

| Service | Usage | Estimated Cost |
|---------|-------|----------------|
| Lambda | 40,000 invocations, 512MB, 5s avg | $0.83 |
| API Gateway | 30,000 requests | $0.04 |
| DynamoDB | 10GB storage, 50K reads, 10K writes | $3.00 |
| SQS | 10,000 requests | $0.00 (free tier) |
| SNS | 10,000 notifications | $0.00 (free tier) |
| Step Functions | 100 executions | $0.03 |
| CloudWatch | Logs + metrics | $2.00 |
| **Total** | | **~$6/month** |

*Actual costs may vary based on usage patterns and AWS pricing changes.*

## Troubleshooting

### Common Issues

#### 1. Deployment Fails

**Error**: "CREATE_FAILED - Resource already exists"
- **Solution**: Delete the existing stack and redeploy, or use a different stack name

#### 2. API Returns 403 Forbidden

**Error**: Missing or invalid API key
- **Solution**: Verify API key is included in `X-API-Key` header
- Get API key from API Gateway console

#### 3. Lambda Timeout

**Error**: "Task timed out after 30 seconds"
- **Solution**: Increase timeout in `template.yaml` under function properties

#### 4. DynamoDB Item Not Found

**Error**: "Order not found"
- **Solution**: Verify order was created successfully, check CloudWatch logs

#### 5. SQS Messages Not Processing

**Error**: Messages stuck in queue
- **Solution**: Check Lambda event source mapping, verify IAM permissions

### Debugging Tips

1. **Check CloudWatch Logs** for all Lambda functions
2. **Use X-Ray** to trace request flow
3. **Verify IAM roles** have necessary permissions
4. **Check DLQ** for failed messages
5. **Test locally** using SAM local:
   ```bash
   sam local start-api
   ```

## Clean Up

To avoid ongoing charges, delete all resources:

```bash
# Delete the CloudFormation stack
sam delete

# Or manually
aws cloudformation delete-stack --stack-name chikwex-order-processing-system
```

This will delete:
- All Lambda functions
- API Gateway
- DynamoDB table (data will be lost!)
- SQS queues
- SNS topics
- Step Functions state machine
- CloudWatch Logs and metrics
- IAM roles

**Note**: Some resources like CloudWatch Logs may take time to fully delete.

## Additional Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Step Functions Patterns](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-patterns.html)
- [API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)

## Assignment Requirements Checklist

- ✅ **API Layer**: REST API with API Gateway, validation, API keys, CORS
- ✅ **Business Logic**: Lambda functions for order creation, processing, notification
- ✅ **Data Layer**: DynamoDB with proper keys, streams, and GSI
- ✅ **Async Processing**: SQS queue with DLQ, SNS topic for fan-out
- ✅ **Orchestration**: Step Functions with retry logic and compensating transactions
- ✅ **Observability**: X-Ray tracing, CloudWatch Logs and metrics
- ✅ **Deliverables**: SAM template, API docs, architecture diagram, testing guide

## License

This project is for educational purposes as part of a serverless architecture assignment.

## Author

Chikwe Azinge - Assignment 3: Serverless Microservices Architecture
