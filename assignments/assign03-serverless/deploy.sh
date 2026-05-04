#!/bin/bash

# Serverless Order Processing System - Deployment Script
# This script automates the build and deployment process

set -e

echo "========================================="
echo "Serverless Order Processing System"
echo "Deployment Script"
echo "========================================="
echo ""

# Check if SAM CLI is installed
if ! command -v sam &> /dev/null; then
    echo "❌ Error: AWS SAM CLI is not installed"
    echo "Please install it from: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ Error: AWS CLI is not configured"
    echo "Please run: aws configure"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Get AWS account info
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

echo "AWS Account: $AWS_ACCOUNT"
echo "AWS Region: $AWS_REGION"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "Step 1: Building SAM application..."
sam build

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build completed successfully"
echo ""

# Check if this is first deployment
if [ "$1" == "--guided" ]; then
    echo "Step 2: Deploying (guided mode)..."
    sam deploy --guided
else
    echo "Step 2: Deploying..."
    sam deploy
fi

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo ""
echo "========================================="
echo "✅ Deployment completed successfully!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Get your API endpoint from the outputs above"
echo "2. Create/retrieve an API key from API Gateway console"
echo "3. Test the API using the examples in README.md"
echo ""
echo "To view stack outputs:"
echo "  aws cloudformation describe-stacks --stack-name <your-stack-name> --query 'Stacks[0].Outputs'"
echo ""
