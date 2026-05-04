#!/bin/bash

echo "========================================="
echo "Setting up Python Virtual Environment"
echo "and Installing AWS SAM CLI"
echo "========================================="
echo ""

# Navigate to project directory
cd "$(dirname "$0")"

# Create virtual environment
echo "Creating virtual environment..."
python3 -m venv venv

if [ $? -ne 0 ]; then
    echo "❌ Failed to create virtual environment"
    echo "Try: sudo apt install python3-venv python3-full"
    exit 1
fi

echo "✅ Virtual environment created"
echo ""

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

echo "✅ Virtual environment activated"
echo ""

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

echo ""

# Install AWS SAM CLI
echo "Installing AWS SAM CLI..."
pip install aws-sam-cli

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ AWS SAM CLI installed successfully!"
    echo ""
    echo "Verifying installation..."
    sam --version
    echo ""
    echo "========================================="
    echo "Setup Complete!"
    echo "========================================="
    echo ""
    echo "To use SAM CLI in the future:"
    echo "1. Activate the virtual environment:"
    echo "   source venv/bin/activate"
    echo ""
    echo "2. Then use SAM commands:"
    echo "   sam build"
    echo "   sam deploy --guided"
    echo ""
    echo "3. To deactivate when done:"
    echo "   deactivate"
    echo ""
else
    echo "❌ Failed to install AWS SAM CLI"
    exit 1
fi
