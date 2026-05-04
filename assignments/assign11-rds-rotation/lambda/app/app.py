"""
Application Lambda – reads credentials from Secrets Manager and connects to RDS.
This simulates an application that must keep working after password rotation.
"""

import boto3
import json
import logging
import os

import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRET_ARN = os.environ["SECRET_ARN"]
_cached_secret = None  # simple in-memory cache within a Lambda container


def lambda_handler(event, context):
    secret = get_secret()
    conn   = None

    try:
        conn = pymysql.connect(
            host=secret["host"],
            user=secret["username"],
            password=secret["password"],
            database=secret.get("dbname"),
            port=int(secret.get("port", 3306)),
            connect_timeout=10,
        )

        with conn.cursor() as cur:
            cur.execute("SELECT VERSION(), NOW(), USER()")
            row = cur.fetchone()

        result = {
            "status":        "connected",
            "mysql_version": row[0],
            "server_time":   str(row[1]),
            "connected_as":  row[2],
        }
        logger.info("Connection successful: %s", result)
        return {"statusCode": 200, "body": json.dumps(result)}

    except pymysql.OperationalError as exc:
        logger.error("Connection failed: %s", exc)
        # Clear the cache so the next invocation re-fetches the secret
        global _cached_secret
        _cached_secret = None
        return {"statusCode": 500, "body": json.dumps({"error": str(exc)})}

    finally:
        if conn:
            conn.close()


def get_secret():
    """Return the current secret dict, using a simple container-level cache."""
    global _cached_secret
    if _cached_secret is not None:
        return _cached_secret

    client   = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=SECRET_ARN)
    secret   = json.loads(response["SecretString"])

    _cached_secret = secret
    logger.info("Fetched secret for user: %s", secret.get("username"))
    return secret
