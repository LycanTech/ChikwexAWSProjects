@echo off
echo =========================================
echo Installing AWS SAM CLI using pip
echo =========================================
echo.

echo Checking Python installation...
python --version
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python from https://www.python.org/downloads/
    pause
    exit /b 1
)

echo.
echo Installing AWS SAM CLI...
pip install aws-sam-cli

echo.
echo Verifying installation...
sam --version

echo.
echo =========================================
echo Installation Complete!
echo =========================================
echo.
echo Next steps:
echo 1. Configure AWS CLI: aws configure
echo 2. Build the project: sam build
echo 3. Deploy: sam deploy --guided
echo.
pause
