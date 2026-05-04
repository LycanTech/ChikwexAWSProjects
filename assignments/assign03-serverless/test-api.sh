#!/bin/bash

# Serverless Order Processing System - API Testing Script
# This script runs a series of tests against the deployed API

echo "========================================="
echo "API Testing Script"
echo "========================================="
echo ""

# Configuration - UPDATE THESE VALUES
API_ENDPOINT="${API_ENDPOINT:-https://your-api-id.execute-api.us-east-1.amazonaws.com/prod}"
API_KEY="${API_KEY:-your-api-key-here}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if variables are set
if [ "$API_ENDPOINT" == "https://your-api-id.execute-api.us-east-1.amazonaws.com/prod" ]; then
    echo -e "${RED}❌ Error: Please set API_ENDPOINT environment variable${NC}"
    echo "Example: export API_ENDPOINT='https://abc123.execute-api.us-east-1.amazonaws.com/prod'"
    exit 1
fi

if [ "$API_KEY" == "your-api-key-here" ]; then
    echo -e "${RED}❌ Error: Please set API_KEY environment variable${NC}"
    echo "Example: export API_KEY='your-api-key'"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "API Endpoint: $API_ENDPOINT"
echo "API Key: ${API_KEY:0:10}..."
echo ""

# Test 1: Create an Order
echo "========================================="
echo -e "${YELLOW}Test 1: Creating an order...${NC}"
echo "========================================="

CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_ENDPOINT}/orders" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{
    "customerId": "CUST-TEST-001",
    "customerEmail": "test@example.com",
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
      "street": "123 Test St",
      "city": "Test City",
      "state": "TC",
      "zipCode": "12345",
      "country": "USA"
    }
  }')

HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$CREATE_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" == "201" ]; then
    echo -e "${GREEN}✅ Test 1 Passed: Order created successfully${NC}"
    echo "Response: $RESPONSE_BODY"

    # Extract order ID for next tests
    ORDER_ID=$(echo "$RESPONSE_BODY" | grep -o '"orderId":"[^"]*' | cut -d'"' -f4)
    echo "Order ID: $ORDER_ID"
else
    echo -e "${RED}❌ Test 1 Failed: Expected 201, got $HTTP_CODE${NC}"
    echo "Response: $RESPONSE_BODY"
    exit 1
fi

echo ""
sleep 2

# Test 2: Get Order by ID
echo "========================================="
echo -e "${YELLOW}Test 2: Retrieving order by ID...${NC}"
echo "========================================="

if [ -z "$ORDER_ID" ]; then
    echo -e "${RED}❌ Test 2 Skipped: No order ID from previous test${NC}"
else
    GET_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${API_ENDPOINT}/orders/${ORDER_ID}" \
      -H "X-API-Key: ${API_KEY}")

    HTTP_CODE=$(echo "$GET_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$GET_RESPONSE" | head -n-1)

    if [ "$HTTP_CODE" == "200" ]; then
        echo -e "${GREEN}✅ Test 2 Passed: Order retrieved successfully${NC}"
        echo "Response: $RESPONSE_BODY"
    else
        echo -e "${RED}❌ Test 2 Failed: Expected 200, got $HTTP_CODE${NC}"
        echo "Response: $RESPONSE_BODY"
    fi
fi

echo ""
sleep 2

# Test 3: List All Orders
echo "========================================="
echo -e "${YELLOW}Test 3: Listing all orders...${NC}"
echo "========================================="

LIST_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${API_ENDPOINT}/orders" \
  -H "X-API-Key: ${API_KEY}")

HTTP_CODE=$(echo "$LIST_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$LIST_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✅ Test 3 Passed: Orders listed successfully${NC}"
    echo "Response: $RESPONSE_BODY"
else
    echo -e "${RED}❌ Test 3 Failed: Expected 200, got $HTTP_CODE${NC}"
    echo "Response: $RESPONSE_BODY"
fi

echo ""
sleep 2

# Test 4: List Orders by Status
echo "========================================="
echo -e "${YELLOW}Test 4: Listing orders by status (PENDING)...${NC}"
echo "========================================="

FILTER_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${API_ENDPOINT}/orders?status=PENDING&limit=10" \
  -H "X-API-Key: ${API_KEY}")

HTTP_CODE=$(echo "$FILTER_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$FILTER_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✅ Test 4 Passed: Filtered orders retrieved successfully${NC}"
    echo "Response: $RESPONSE_BODY"
else
    echo -e "${RED}❌ Test 4 Failed: Expected 200, got $HTTP_CODE${NC}"
    echo "Response: $RESPONSE_BODY"
fi

echo ""
sleep 2

# Test 5: Invalid Order (Missing Required Fields)
echo "========================================="
echo -e "${YELLOW}Test 5: Testing validation (missing required field)...${NC}"
echo "========================================="

INVALID_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_ENDPOINT}/orders" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{
    "items": [
      {
        "productId": "PROD-001",
        "quantity": 1,
        "price": 29.99
      }
    ]
  }')

HTTP_CODE=$(echo "$INVALID_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$INVALID_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" == "400" ]; then
    echo -e "${GREEN}✅ Test 5 Passed: Validation working correctly${NC}"
    echo "Response: $RESPONSE_BODY"
else
    echo -e "${RED}❌ Test 5 Failed: Expected 400, got $HTTP_CODE${NC}"
    echo "Response: $RESPONSE_BODY"
fi

echo ""
sleep 2

# Test 6: Get Non-Existent Order
echo "========================================="
echo -e "${YELLOW}Test 6: Testing 404 response (non-existent order)...${NC}"
echo "========================================="

NOT_FOUND_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "${API_ENDPOINT}/orders/non-existent-id-12345" \
  -H "X-API-Key: ${API_KEY}")

HTTP_CODE=$(echo "$NOT_FOUND_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$NOT_FOUND_RESPONSE" | head -n-1)

if [ "$HTTP_CODE" == "404" ]; then
    echo -e "${GREEN}✅ Test 6 Passed: 404 handling working correctly${NC}"
    echo "Response: $RESPONSE_BODY"
else
    echo -e "${RED}❌ Test 6 Failed: Expected 404, got $HTTP_CODE${NC}"
    echo "Response: $RESPONSE_BODY"
fi

echo ""
echo "========================================="
echo -e "${GREEN}Testing Complete!${NC}"
echo "========================================="
echo ""
echo "Summary:"
echo "- Created order with ID: $ORDER_ID"
echo "- Retrieved order successfully"
echo "- Listed all orders"
echo "- Filtered orders by status"
echo "- Validated input validation"
echo "- Tested error handling"
echo ""
echo "Next Steps:"
echo "1. Check CloudWatch Logs for Lambda execution logs"
echo "2. View X-Ray traces for request flows"
echo "3. Check CloudWatch Metrics for custom metrics"
echo "4. Monitor SQS queue for order processing"
echo ""
