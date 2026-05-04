#!/bin/bash

echo "========================================="
echo "AWS CLI Configuration Helper"
echo "========================================="
echo ""
echo "This script will help you configure AWS CLI with your credentials."
echo ""
echo "You'll need:"
echo "  1. AWS Access Key ID"
echo "  2. AWS Secret Access Key"
echo "  3. Default region (e.g., us-east-1)"
echo ""
echo "Let's get started!"
echo ""

# Run AWS configure
python -m awscli configure

echo ""
echo "========================================="
echo "Verifying Configuration..."
echo "========================================="
echo ""

# Test the configuration
echo "Testing AWS credentials..."
python -m awscli sts get-caller-identity

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ AWS CLI configured successfully!"
    echo ""
    echo "You're now ready to deploy!"
else
    echo ""
    echo "❌ Configuration failed. Please check your credentials and try again."
    echo ""
    exit 1
fi
