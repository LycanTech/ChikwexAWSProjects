# AWS SAM CLI Installation Guide

## For Windows

### Method 1: MSI Installer (Recommended)

1. **Download the SAM CLI installer:**
   - Go to: https://github.com/aws/aws-sam-cli/releases/latest
   - Download `AWS_SAM_CLI_64_PY3.msi`
   - Or use direct link: https://github.com/aws/aws-sam-cli/releases/latest/download/AWS_SAM_CLI_64_PY3.msi

2. **Run the installer:**
   - Double-click the downloaded `.msi` file
   - Follow the installation wizard
   - Accept the license agreement
   - Choose installation location (default is fine)
   - Click "Install"

3. **Verify installation:**
   Open a **new** Command Prompt or PowerShell and run:
   ```bash
   sam --version
   ```

   You should see output like:
   ```
   SAM CLI, version 1.108.0
   ```

### Method 2: Using Chocolatey

If you have Chocolatey package manager installed:

```powershell
# Run PowerShell as Administrator
choco install aws-sam-cli
```

### Method 3: Using pip (Python)

If you have Python 3.8+ installed:

```bash
# Install SAM CLI
pip install aws-sam-cli

# Verify
sam --version
```

## Prerequisites

Before installing SAM CLI, ensure you have:

### 1. AWS CLI

**Check if installed:**
```bash
aws --version
```

**If not installed, install AWS CLI:**
- Download from: https://aws.amazon.com/cli/
- Or use MSI: https://awscli.amazonaws.com/AWSCLIV2.msi
- Run installer and follow prompts

**Configure AWS CLI:**
```bash
aws configure
```

You'll need:
- AWS Access Key ID
- AWS Secret Access Key
- Default region (e.g., `us-east-1`)
- Default output format (choose `json`)

### 2. Docker Desktop (Optional, for local testing)

**Download from:** https://www.docker.com/products/docker-desktop/

SAM can run without Docker, but you'll need it for:
- `sam local start-api` (testing locally)
- `sam local invoke` (invoking functions locally)

**Note:** You can deploy to AWS without Docker!

## Post-Installation Steps

### 1. Verify SAM CLI

```bash
sam --version
```

### 2. Verify AWS CLI

```bash
aws --version
aws sts get-caller-identity
```

The second command should show your AWS account info.

### 3. Verify Python (for Lambda functions)

```bash
python --version
```

Should be Python 3.11 or later.

## Common Installation Issues

### Issue: "sam is not recognized"

**Solution:**
- Close and reopen your terminal/Command Prompt
- Or restart your computer
- Or manually add SAM to PATH:
  - Default location: `C:\Program Files\Amazon\AWSSAMCLI\bin\`
  - Add to System Environment Variables → Path

### Issue: "AWS credentials not configured"

**Solution:**
```bash
aws configure
```

Enter your AWS credentials.

### Issue: Python version too old

**Solution:**
- Download Python 3.11+: https://www.python.org/downloads/
- During installation, check "Add Python to PATH"

## Quick Test

After installation, test with:

```bash
# Create a test app
sam init --runtime python3.11 --name test-app --app-template hello-world --no-tracing

# Navigate to the app
cd test-app

# Build it
sam build

# If Docker is installed, test locally:
sam local start-api

# Deploy to AWS
sam deploy --guided
```

## Installation Complete!

Once SAM CLI is installed and verified, you can deploy the ChikwexServerlessAssign3 project:

```bash
cd ChikwexServerlessAssign3
sam build
sam deploy --guided
```

## Additional Resources

- [Official SAM Installation Guide](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
- [SAM CLI Documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/what-is-sam.html)
- [AWS Free Tier](https://aws.amazon.com/free/) - Most resources in this project are free tier eligible
