import json
import random
import time
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Simulated users and operations
USERS = ["user_001", "user_002", "user_003", "user_004", "user_005"]
OPERATIONS = ["GET /api/products", "POST /api/orders", "GET /api/users", "DELETE /api/cart", "PUT /api/profile"]
ERROR_CODES = [500, 503, 404, 401, 429]

def lambda_handler(event, context):
    """
    Simulates an API endpoint that logs structured JSON.
    - INFO  = successful requests (response time < 500ms)
    - WARN  = slow requests (response time >= 500ms)
    - ERROR = failed requests with HTTP error codes
    """

    user_id    = random.choice(USERS)
    operation  = random.choice(OPERATIONS)
    outcome    = random.choices(["success", "slow", "error"], weights=[65, 20, 15])[0]

    if outcome == "success":
        response_time = random.randint(50, 499)
        log_entry = {
            "level":         "INFO",
            "user_id":       user_id,
            "operation":     operation,
            "response_time": response_time,
            "status":        "success",
            "message":       "Request completed successfully"
        }
        logger.info(json.dumps(log_entry))
        return {"statusCode": 200, "body": "OK"}

    elif outcome == "slow":
        response_time = random.randint(500, 2000)
        log_entry = {
            "level":         "WARN",
            "user_id":       user_id,
            "operation":     operation,
            "response_time": response_time,
            "status":        "slow",
            "message":       f"Slow operation detected: {response_time}ms exceeds 500ms threshold"
        }
        logger.warning(json.dumps(log_entry))
        return {"statusCode": 200, "body": "OK (slow)"}

    else:  # error
        response_time = random.randint(100, 800)
        error_code    = random.choice(ERROR_CODES)
        log_entry = {
            "level":         "ERROR",
            "user_id":       user_id,
            "operation":     operation,
            "response_time": response_time,
            "status":        "error",
            "error_code":    error_code,
            "message":       f"Request failed with HTTP {error_code}"
        }
        logger.error(json.dumps(log_entry))
        return {"statusCode": error_code, "body": f"Error {error_code}"}
