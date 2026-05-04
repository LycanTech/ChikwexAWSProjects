"""
RDS Password Rotation Lambda

Implements the four-step Secrets Manager rotation protocol:
  createSecret  → generate and store AWSPENDING version
  setSecret     → create new DB user with new password
  testSecret    → verify connection works with new credentials
  finishSecret  → promote AWSPENDING to AWSCURRENT, delete old user
"""

import boto3
import json
import logging
import os
import secrets
import string

import pymysql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRETS_MANAGER_ENDPOINT = os.environ.get("SECRETS_MANAGER_ENDPOINT")


def get_client():
    return boto3.client(
        "secretsmanager",
        endpoint_url=SECRETS_MANAGER_ENDPOINT,
    )


def lambda_handler(event, context):
    arn   = event["SecretId"]
    token = event["ClientRequestToken"]
    step  = event["Step"]

    client = get_client()

    # Verify the secret exists and the token matches a pending stage
    metadata = client.describe_secret(SecretId=arn)
    if not metadata.get("RotationEnabled"):
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    versions = metadata.get("VersionIdsToStages", {})
    if token not in versions:
        raise ValueError(f"Token {token} not found in secret versions")

    if "AWSCURRENT" in versions[token]:
        logger.info("Version %s already AWSCURRENT – nothing to do", token)
        return
    if "AWSPENDING" not in versions[token]:
        raise ValueError(f"Token {token} is not AWSPENDING")

    logger.info("Step: %s | Secret: %s | Token: %s", step, arn, token)

    if step == "createSecret":
        create_secret(client, arn, token)
    elif step == "setSecret":
        set_secret(client, arn, token)
    elif step == "testSecret":
        test_secret(client, arn, token)
    elif step == "finishSecret":
        finish_secret(client, arn, token)
    else:
        raise ValueError(f"Unknown rotation step: {step}")


# ---------------------------------------------------------------------------
# Step 1 – createSecret
# ---------------------------------------------------------------------------
def create_secret(client, arn, token):
    """Generate a new random password and store it as AWSPENDING."""
    # Check if AWSPENDING already exists (idempotency)
    try:
        client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING")
        logger.info("AWSPENDING already exists – skipping createSecret")
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    # Get current secret to copy metadata
    current = get_secret_dict(client, arn, "AWSCURRENT")

    # Generate a strong random password (no special chars that break MySQL)
    alphabet = string.ascii_letters + string.digits + "!#$%^&*()-_=+"
    new_password = "".join(secrets.choice(alphabet) for _ in range(32))

    # Build new secret – new username derived from token (first 8 chars)
    new_secret = dict(current)
    new_secret["password"] = new_password
    new_secret["username"] = f"rot_{token[:8]}"

    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(new_secret),
        VersionStages=["AWSPENDING"],
    )
    logger.info("AWSPENDING secret created with new username: %s", new_secret["username"])


# ---------------------------------------------------------------------------
# Step 2 – setSecret
# ---------------------------------------------------------------------------
def set_secret(client, arn, token):
    """Create a new MySQL user with the AWSPENDING credentials."""
    pending = get_secret_dict(client, arn, "AWSPENDING")
    current = get_secret_dict(client, arn, "AWSCURRENT")

    conn = connect_db(current)
    try:
        with conn.cursor() as cur:
            new_user = pending["username"]
            new_pass = pending["password"]
            db_name  = pending.get("dbname", "%")

            # Create the new user
            cur.execute(
                "CREATE USER IF NOT EXISTS %s@'%%' IDENTIFIED BY %s",
                (new_user, new_pass),
            )
            # Grant same privileges as current user on the target database
            cur.execute(
                f"GRANT ALL PRIVILEGES ON `{db_name}`.* TO %s@'%%'",
                (new_user,),
            )
            cur.execute("FLUSH PRIVILEGES")
            conn.commit()
            logger.info("Created MySQL user: %s", new_user)
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Step 3 – testSecret
# ---------------------------------------------------------------------------
def test_secret(client, arn, token):
    """Verify the AWSPENDING credentials can connect to the database."""
    pending = get_secret_dict(client, arn, "AWSPENDING")
    conn = connect_db(pending)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            result = cur.fetchone()
            if result[0] != 1:
                raise RuntimeError("Test query did not return expected result")
        logger.info("Connection test successful for user: %s", pending["username"])
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Step 4 – finishSecret
# ---------------------------------------------------------------------------
def finish_secret(client, arn, token):
    """Promote AWSPENDING → AWSCURRENT and delete the old DB user."""
    metadata = client.describe_secret(SecretId=arn)
    versions = metadata["VersionIdsToStages"]

    # Find the current version ID so we can demote it
    current_version = None
    for vid, stages in versions.items():
        if "AWSCURRENT" in stages and vid != token:
            current_version = vid
            break

    # Get old username before promoting (so we can delete it)
    old_secret = get_secret_dict(client, arn, "AWSCURRENT")
    old_user   = old_secret["username"]

    # Promote AWSPENDING to AWSCURRENT
    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info("Promoted token %s to AWSCURRENT", token)

    # Delete the old DB user
    new_secret = get_secret_dict(client, arn, "AWSCURRENT")
    conn = connect_db(new_secret)
    try:
        with conn.cursor() as cur:
            # Only drop if it's not the original bootstrap admin
            if old_user != new_secret.get("admin_username", "admin"):
                cur.execute("DROP USER IF EXISTS %s@'%%'", (old_user,))
                conn.commit()
                logger.info("Deleted old MySQL user: %s", old_user)
            else:
                logger.info("Skipping drop of bootstrap admin user: %s", old_user)
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def get_secret_dict(client, arn, stage, token=None):
    kwargs = {"SecretId": arn, "VersionStage": stage}
    if token:
        kwargs["VersionId"] = token
    response = client.get_secret_value(**kwargs)
    return json.loads(response["SecretString"])


def connect_db(secret):
    return pymysql.connect(
        host=secret["host"],
        user=secret["username"],
        password=secret["password"],
        database=secret.get("dbname"),
        port=int(secret.get("port", 3306)),
        connect_timeout=10,
        autocommit=False,
    )
