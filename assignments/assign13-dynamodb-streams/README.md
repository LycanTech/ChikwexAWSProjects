# Assignment 13 – DynamoDB Streams with Lambda Aggregation

## Overview

Build a real-time analytics pipeline using DynamoDB Streams and AWS Lambda. When orders are written to a DynamoDB table, a stream triggers a Lambda function that aggregates sales totals per customer in a second table.

---

## Architecture

```
[ Insert 50 Random Orders ]
         |
         v
  [ DynamoDB: Orders ]  ──── TTL (7 days) ──── GSI on "status"
         |
  [ DynamoDB Stream ]
         |
         v
  [ Lambda: Aggregator ]
         |
         v
  [ DynamoDB: CustomerStats ]
         |
         v
  [ Query: Real-time Sales Totals ]
```

---

## Resources to Create

### 1. DynamoDB Table – `Orders`
- **Partition Key**: `orderId` (String)
- **Attributes**: `customerId`, `amount`, `status`, `timestamp`
- **DynamoDB Streams**: Enabled (NEW_AND_OLD_IMAGES)
- **TTL**: Enabled on `timestamp` attribute (expire after 7 days)
- **GSI**: On `status` field to query orders by status

### 2. DynamoDB Table – `CustomerStats`
- **Partition Key**: `customerId` (String)
- **Attributes**: `totalSales` (Number), `orderCount` (Number)

### 3. Lambda Function – `OrderAggregator`
- **Trigger**: DynamoDB Stream on `Orders` table
- **Purpose**: Reads INSERT events from the stream, updates running `totalSales` and `orderCount` in `CustomerStats` using atomic counter updates

### 4. Lambda Function – `OrderSeeder`
- **Purpose**: Inserts 50 random orders into the `Orders` table to test the pipeline

---

## Step-by-Step Implementation

### Step 1 – Create the `Orders` DynamoDB Table
- Table name: `Orders`
- Partition key: `orderId` (String)
- Enable DynamoDB Streams with view type: **NEW_AND_OLD_IMAGES**

### Step 2 – Enable TTL on `Orders`
- TTL attribute name: `expiresAt`
- Orders will be set to expire 7 days from insertion time (stored as a Unix epoch timestamp)

### Step 3 – Add a GSI on `status`
- Index name: `status-index`
- Partition key: `status` (String)
- Enables querying all orders with a given status (e.g., `PENDING`, `COMPLETE`)

### Step 4 – Create the `CustomerStats` Table
- Table name: `CustomerStats`
- Partition key: `customerId` (String)

### Step 5 – Create the `OrderAggregator` Lambda
- Runtime: Python 3.12
- Trigger: DynamoDB Stream from `Orders`
- Batch size: 100
- Logic:
  - On each INSERT event, extract `customerId` and `amount`
  - Use `ADD` in an UpdateExpression to atomically increment `totalSales` and `orderCount`

### Step 6 – Create the `OrderSeeder` Lambda
- Runtime: Python 3.12
- No trigger (invoked manually)
- Inserts 50 items with random `orderId`, `customerId`, `amount`, and `status`
- Sets `expiresAt` = current Unix time + 604800 (7 days)

### Step 7 – Test and Verify
- Invoke `OrderSeeder` manually
- Query `CustomerStats` to confirm aggregations are updating in real-time
- Use the `status-index` GSI to query orders by status
- Verify stream events process within seconds

---

## Success Criteria

| Criteria | Expected Result |
|---|---|
| Streams process within seconds | Lambda triggered immediately after insert |
| Aggregations are accurate | `totalSales` matches sum of all amounts per customer |
| GSI queries work correctly | Can filter orders by `status` |
| Real-time aggregate visible | `CustomerStats` updates after every batch |

---

## Files

| File | Description |
|---|---|
| `order_aggregator.py` | Lambda – processes stream events, updates CustomerStats |
| `order_seeder.py` | Lambda – inserts 50 random orders into Orders table |
| `setup.sh` | Shell script to create all AWS resources via CLI |

---

## AWS CLI Quick Reference

```bash
# Query CustomerStats for a specific customer
aws dynamodb get-item \
  --table-name CustomerStats \
  --key '{"customerId": {"S": "customer-1"}}'

# Query Orders by status using GSI
aws dynamodb query \
  --table-name Orders \
  --index-name status-index \
  --key-condition-expression "#s = :status" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":status": {"S": "COMPLETE"}}'
```
