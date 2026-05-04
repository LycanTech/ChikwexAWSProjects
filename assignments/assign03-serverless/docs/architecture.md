# Serverless Order Processing System - Architecture

## Overview

This document describes the architecture of the serverless order processing system for an e-commerce platform. The system is built using AWS serverless services to provide a scalable, cost-effective, and highly available solution.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CLIENT APPLICATION                                 │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             │ HTTPS Requests
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         API GATEWAY (REST API)                               │
│  ┌──────────────┬─────────────────┬────────────────────────────────┐       │
│  │ POST /orders │ GET /orders/{id}│ GET /orders?status=PENDING     │       │
│  └──────┬───────┴────────┬────────┴─────────┬──────────────────────┘       │
│         │                │                  │                               │
│         │  API Key Auth  │  CORS Enabled    │  Request Validation          │
└─────────┼────────────────┼──────────────────┼───────────────────────────────┘
          │                │                  │
          ▼                ▼                  ▼
┌──────────────────┐ ┌────────────────┐ ┌────────────────────┐
│   Lambda:        │ │   Lambda:      │ │   Lambda:          │
│ Order Creation   │ │ Order Retrieval│ │ Order Retrieval    │
│                  │ │  (by ID)       │ │  (list all)        │
└────┬─────────────┘ └───────┬────────┘ └──────┬─────────────┘
     │                       │                   │
     │ 1. Validate           │                   │
     │ 2. Generate ID        │                   │
     │ 3. Calculate Total    │                   │
     │                       │                   │
     ▼                       ▼                   ▼
┌─────────────────────────────────────────────────────────────┐
│                    DynamoDB Table: Orders                    │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Partition Key: orderId (String)                   │     │
│  │  Sort Key: createdAt (String)                      │     │
│  │  Attributes: customerId, items, status, total, etc │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  Global Secondary Index (GSI): status-index                 │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Partition Key: status                             │     │
│  │  Sort Key: createdAt                               │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  DynamoDB Streams: Enabled (NEW_AND_OLD_IMAGES)             │
└──────┬───────────────────────────────────────────────────────┘
       │
       │ Stream Events
       │ (Order Created/Updated)
       │
┌──────▼──────────────────────────────────────────────────────┐
│                      SQS Queue                               │
│              order-processing-queue                          │
│  ┌──────────────────────────────────────────────────┐       │
│  │ VisibilityTimeout: 180s                          │       │
│  │ MessageRetentionPeriod: 14 days                  │       │
│  │ Batch Size: 10                                   │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
│  Dead Letter Queue (DLQ)                                    │
│  ┌──────────────────────────────────────────────────┐       │
│  │ MaxReceiveCount: 3                               │       │
│  │ Stores failed messages for analysis              │       │
│  └──────────────────────────────────────────────────┘       │
└──────┬───────────────────────────────────────────────────────┘
       │
       │ Trigger (Batch Processing)
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│              Lambda: Order Processing                        │
│  ┌──────────────────────────────────────────────────┐       │
│  │ 1. Update order status to PROCESSING             │       │
│  │ 2. Process payment (simulated)                   │       │
│  │ 3. Update inventory (simulated)                  │       │
│  │ 4. Handle compensating transactions              │       │
│  │ 5. Publish to SNS topic                          │       │
│  └──────────────────────────────────────────────────┘       │
└──────┬───────────────────────────────────────────────────────┘
       │
       │ Publish Events
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                   SNS Topic                                  │
│              order-notifications                             │
│  ┌──────────────────────────────────────────────────┐       │
│  │ Fan-out architecture for multiple subscribers    │       │
│  │ Delivers messages to all subscribed endpoints    │       │
│  └──────────────────────────────────────────────────┘       │
└──────┬───────────────────────────────────────────────────────┘
       │
       │ SNS Subscription
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│           Lambda: Order Notification                         │
│  ┌──────────────────────────────────────────────────┐       │
│  │ 1. Parse notification event                      │       │
│  │ 2. Send email via SES (optional)                 │       │
│  │ 3. Send SMS via SNS (optional)                   │       │
│  │ 4. Log notification delivery                     │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              Step Functions State Machine                    │
│              order-workflow (Alternative Flow)               │
│  ┌──────────────────────────────────────────────────┐       │
│  │ 1. Validate Order                                │       │
│  │         ▼                                        │       │
│  │ 2. Process Payment                               │       │
│  │         ▼                                        │       │
│  │ 3. Update Inventory                              │       │
│  │         ▼                                        │       │
│  │ 4. Update Order Status (COMPLETED)               │       │
│  │         ▼                                        │       │
│  │ 5. Send Success Notification                     │       │
│  │                                                  │       │
│  │ Error Handling:                                  │       │
│  │ - Retry logic with exponential backoff           │       │
│  │ - Compensating transactions (refunds)            │       │
│  │ - Failure notifications                          │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY LAYER                       │
│  ┌──────────────────────────────────────────────────┐       │
│  │ X-Ray Tracing                                    │       │
│  │ - End-to-end request tracing                     │       │
│  │ - Service map visualization                      │       │
│  │ - Performance bottleneck identification          │       │
│  └──────────────────────────────────────────────────┘       │
│  ┌──────────────────────────────────────────────────┐       │
│  │ CloudWatch Logs                                  │       │
│  │ - Lambda function logs (7 day retention)         │       │
│  │ - Log Insights queries                           │       │
│  │ - Structured logging                             │       │
│  └──────────────────────────────────────────────────┘       │
│  ┌──────────────────────────────────────────────────┐       │
│  │ CloudWatch Metrics                               │       │
│  │ - Custom metrics: OrdersCreated, OrderValue      │       │
│  │ - Lambda metrics: Invocations, Errors, Duration  │       │
│  │ - DynamoDB metrics: Consumed capacity            │       │
│  └──────────────────────────────────────────────────┘       │
│  ┌──────────────────────────────────────────────────┐       │
│  │ CloudWatch Alarms                                │       │
│  │ - High error rate alarm                          │       │
│  │ - DLQ messages alarm                             │       │
│  │ - Lambda throttling alarm                        │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

## Event Flow

### Order Creation Flow

1. **Client Request**: Client sends POST request to `/orders` endpoint
2. **API Gateway**: Validates request, checks API key, applies CORS
3. **Order Creation Lambda**:
   - Validates order data (required fields, item quantities, prices)
   - Generates unique order ID (UUID)
   - Calculates total amount
   - Saves order to DynamoDB with status "PENDING"
   - Sends message to SQS queue for processing
   - Publishes custom CloudWatch metrics
   - Returns order details to client
4. **SQS Queue**: Buffers order processing messages
5. **Order Processing Lambda** (triggered by SQS):
   - Updates order status to "PROCESSING"
   - Publishes notification to SNS topic
6. **SNS Topic**: Distributes notification to subscribers
7. **Order Notification Lambda**:
   - Sends email/SMS notifications to customer
   - Logs delivery status

### Order Retrieval Flow

1. **Client Request**: GET `/orders/{id}` or GET `/orders?status=PENDING`
2. **API Gateway**: Routes request to Order Retrieval Lambda
3. **Order Retrieval Lambda**:
   - Queries DynamoDB by order ID or status
   - Returns order(s) to client

### Step Functions Workflow (Alternative Processing)

For complex order processing scenarios:

1. **Validate Order**: Retrieves order from DynamoDB
2. **Process Payment**: Calls payment processing function
3. **Update Inventory**: Updates inventory levels
4. **Update Order Status**: Marks order as COMPLETED
5. **Send Notification**: Publishes success notification

**Error Handling**:
- Automatic retries with exponential backoff
- Compensating transactions (payment refunds)
- Failed order marking with error details

## AWS Services Used

### Compute
- **AWS Lambda**: Serverless compute for all business logic
  - Order Creation Function
  - Order Retrieval Function
  - Order Processing Function
  - Order Notification Function

### API
- **API Gateway**: REST API with API key authentication, CORS, request validation

### Data Storage
- **DynamoDB**: NoSQL database for order storage
  - Primary Index: orderId + createdAt
  - GSI: status + createdAt (for filtering by order status)
  - DynamoDB Streams for change data capture

### Messaging & Queuing
- **SQS**: Message queue for asynchronous order processing
  - Standard queue with Dead Letter Queue (DLQ)
  - Batch processing with visibility timeout
- **SNS**: Pub/sub messaging for notifications
  - Fan-out to multiple subscribers
  - Email/SMS delivery

### Orchestration
- **Step Functions**: Workflow orchestration for complex order processing
  - State machine with error handling
  - Retry logic and compensating transactions

### Observability
- **X-Ray**: Distributed tracing for end-to-end visibility
- **CloudWatch Logs**: Centralized logging with 7-day retention
- **CloudWatch Metrics**: Custom and AWS metrics
- **CloudWatch Alarms**: Proactive monitoring and alerting

## Security Features

1. **API Authentication**: API key required for all endpoints
2. **IAM Roles**: Least privilege access for Lambda functions
3. **Encryption**: Data encrypted at rest (DynamoDB) and in transit (HTTPS)
4. **CORS**: Configured to allow specific origins
5. **Request Validation**: Input validation at API Gateway and Lambda layers

## Scalability Features

1. **Auto-scaling**: All services automatically scale based on demand
2. **Queue Buffering**: SQS absorbs traffic spikes
3. **Batch Processing**: SQS triggers process messages in batches (up to 10)
4. **DynamoDB On-Demand**: Pay-per-request billing with automatic scaling
5. **Lambda Concurrency**: Handles thousands of concurrent executions

## Cost Optimization

1. **Pay-per-use**: No servers to manage, pay only for actual usage
2. **DynamoDB On-Demand**: No capacity planning required
3. **Lambda Optimization**: Right-sized memory and timeout settings
4. **Log Retention**: 7-day retention to control costs
5. **Reserved Concurrency**: Optional for predictable workloads

## High Availability & Reliability

1. **Multi-AZ Deployment**: All services deployed across multiple availability zones
2. **Retry Logic**: Automatic retries with exponential backoff
3. **Dead Letter Queue**: Captures failed messages for analysis
4. **Circuit Breaker**: Step Functions handles cascading failures
5. **Compensating Transactions**: Automatic rollback on failures

## Monitoring & Alerting

1. **Error Rate Monitoring**: Alerts when Lambda errors exceed threshold
2. **DLQ Monitoring**: Alerts when messages land in dead letter queue
3. **Custom Metrics**: Track business metrics (orders created, order value)
4. **Log Insights**: Query logs for troubleshooting
5. **X-Ray Service Map**: Visualize service dependencies and performance
