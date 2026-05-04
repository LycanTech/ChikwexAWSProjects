# Quick Start Guide

Get up and running with the Serverless Order Processing System in under 15 minutes!

## Prerequisites Checklist

- [ ] AWS Account with admin access
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] AWS SAM CLI installed (`sam --version`)
- [ ] Python 3.11+ installed

## 5-Minute Deployment

### Step 1: Navigate to Project Directory

```bash
cd ChikwexServerlessAssign3
```

### Step 2: Build and Deploy

```bash
# Build the application
sam build

# Deploy (first time - guided mode)
sam deploy --guided
```

**Guided deployment prompts:**
- Stack Name: `chikwex-order-system` (or your choice)
- AWS Region: `us-east-1` (or your preferred region)
- Confirm changes: `Y`
- Allow SAM CLI IAM role creation: `Y`
- Save arguments to configuration: `Y`

**Wait ~5-10 minutes** for deployment to complete.

### Step 3: Get API Credentials

After deployment, note these values from the output:

```
ApiEndpoint: https://xxxxx.execute-api.us-east-1.amazonaws.com/prod
```

Get your API key:

1. Go to AWS Console → API Gateway
2. Select your API → API Keys
3. Create new key OR use existing
4. Copy the API key value

### Step 4: Test the API

**Set environment variables:**

```bash
# Linux/Mac
export API_ENDPOINT="https://xxxxx.execute-api.us-east-1.amazonaws.com/prod"
export API_KEY="your-api-key-here"

# Windows (PowerShell)
$env:API_ENDPOINT="https://xxxxx.execute-api.us-east-1.amazonaws.com/prod"
$env:API_KEY="your-api-key-here"

# Windows (Command Prompt)
set API_ENDPOINT=https://xxxxx.execute-api.us-east-1.amazonaws.com/prod
set API_KEY=your-api-key-here
```

**Create an order:**

```bash
curl -X POST "${API_ENDPOINT}/orders" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: ${API_KEY}" \
  -d '{
    "customerId": "CUST-001",
    "customerEmail": "test@example.com",
    "items": [
      {"productId": "PROD-001", "quantity": 2, "price": 29.99}
    ]
  }'
```

**Expected response:**

```json
{
  "message": "Order created successfully",
  "orderId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "PENDING",
  "totalAmount": 59.98,
  "createdAt": "2024-01-15T10:30:00Z"
}
```

## Quick Testing Script

For automated testing:

```bash
# Linux/Mac
chmod +x test-api.sh
./test-api.sh

# Windows (Git Bash)
bash test-api.sh
```

## Viewing Logs

**CloudWatch Logs:**

```bash
# View order creation logs
aws logs tail /aws/lambda/your-stack-name-order-creation --follow

# View order processing logs
aws logs tail /aws/lambda/your-stack-name-order-processing --follow
```

**X-Ray Traces:**

1. AWS Console → X-Ray → Service map
2. View request traces and service dependencies

## Common First-Time Issues

### Issue: "API Key not valid"

**Solution:**
1. Verify API key is associated with usage plan
2. Check API Gateway → Usage Plans → Add API Key

### Issue: "403 Forbidden"

**Solution:**
- Include `X-API-Key` header in all requests
- Verify API key value is correct

### Issue: "Stack already exists"

**Solution:**
- Use a different stack name, OR
- Delete existing stack: `sam delete`

## Next Steps

1. ✅ **Read the Full README**: [README.md](README.md)
2. ✅ **Review Architecture**: [docs/architecture.md](docs/architecture.md)
3. ✅ **API Documentation**: [docs/api-specification.yaml](docs/api-specification.yaml)
4. ✅ **Monitor**: Check CloudWatch metrics and X-Ray traces
5. ✅ **Customize**: Modify Lambda functions for your use case

## Cleanup

When done testing:

```bash
sam delete
```

This removes all AWS resources and stops billing.

## Support

For issues or questions:
- Check [README.md](README.md) troubleshooting section
- Review CloudWatch logs
- Check AWS service quotas

---

**Estimated cost for testing**: <$1 for a few hours of testing (within free tier for most services)

**Time to first order**: ~15 minutes from start to finish!
