import boto3
import json
import time
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client("ssm")
asg_client = boto3.client("autoscaling")


def wait_for_ssm_agent(instance_id: str, max_retries: int = 20, delay: int = 15) -> bool:
    """
    Poll SSM until the instance shows as 'Online'.
    The SSM agent may take a minute or two to register after boot.
    """
    for attempt in range(1, max_retries + 1):
        logger.info("SSM agent check %d/%d for %s", attempt, max_retries, instance_id)
        resp = ssm_client.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        )
        items = resp.get("InstanceInformationList", [])
        if items and items[0].get("PingStatus") == "Online":
            logger.info("SSM agent is Online for %s", instance_id)
            return True
        time.sleep(delay)
    return False


def run_setup_commands(instance_id: str) -> str:
    """
    Send a shell script via SSM Run Command that:
      1. Installs httpd and stress
      2. Fetches instance metadata (IMDSv2)
      3. Writes a unique index.html
      4. Enables and starts httpd
    Returns the final SSM command status.
    """
    # Each list item is executed as a separate shell command by AWS-RunShellScript.
    # We embed the metadata fetch + HTML write as a single inline bash block so
    # variable expansion works correctly.
    commands = [
        # ── 1. Install packages ────────────────────────────────────────────────
        "dnf install -y httpd stress",

        # ── 2. Fetch IMDSv2 token (required on AL2023) ─────────────────────────
        'TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" '
        '-H "X-aws-ec2-metadata-token-ttl-seconds: 21600")',

        # ── 3. Collect instance metadata ───────────────────────────────────────
        'INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" '
        "http://169.254.169.254/latest/meta-data/instance-id)",
        'AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" '
        "http://169.254.169.254/latest/meta-data/placement/availability-zone)",
        'LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" '
        "http://169.254.169.254/latest/meta-data/local-ipv4)",
        'INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" '
        "http://169.254.169.254/latest/meta-data/instance-type)",
        'LAUNCH_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")',

        # ── 4. Write the unique index.html ─────────────────────────────────────
        'cat > /var/www/html/index.html << EOF\n'
        "<!DOCTYPE html>\n"
        "<html>\n"
        "<head><title>ASG Instance - \$INSTANCE_ID</title>"
        "<style>body{font-family:Arial,sans-serif;max-width:600px;margin:50px auto;}"
        "h1{color:#232f3e;}table{border-collapse:collapse;width:100%;}"
        "td,th{border:1px solid #ddd;padding:8px;}"
        "th{background:#232f3e;color:white;}</style></head>\n"
        "<body>\n"
        "<h1>Auto-Configured Web Server</h1>\n"
        "<table>\n"
        "<tr><th>Metadata</th><th>Value</th></tr>\n"
        "<tr><td>Instance ID</td><td>\$INSTANCE_ID</td></tr>\n"
        "<tr><td>Availability Zone</td><td>\$AZ</td></tr>\n"
        "<tr><td>Private IP</td><td>\$LOCAL_IP</td></tr>\n"
        "<tr><td>Instance Type</td><td>\$INSTANCE_TYPE</td></tr>\n"
        "<tr><td>Launch Time (UTC)</td><td>\$LAUNCH_TIME</td></tr>\n"
        "</table>\n"
        "</body>\n"
        "</html>\n"
        "EOF",

        # ── 5. Enable and start httpd ──────────────────────────────────────────
        "systemctl enable httpd",
        "systemctl start httpd",
    ]

    resp = ssm_client.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": commands},
        TimeoutSeconds=300,
        Comment=f"ASG lifecycle setup for {instance_id}",
    )
    command_id = resp["Command"]["CommandId"]
    logger.info("SSM command %s sent to %s", command_id, instance_id)

    # Poll until the command finishes (max ~5 min)
    terminal_states = {"Success", "Failed", "Cancelled", "TimedOut", "DeliveryTimedOut"}
    for _ in range(30):
        time.sleep(10)
        result = ssm_client.get_command_invocation(
            CommandId=command_id, InstanceId=instance_id
        )
        status = result["Status"]
        logger.info("SSM command status: %s", status)
        if status in terminal_states:
            if status != "Success":
                logger.error("SSM stdout: %s", result.get("StandardOutputContent", ""))
                logger.error("SSM stderr: %s", result.get("StandardErrorContent", ""))
            return status

    return "TimedOut"


def complete_lifecycle(hook_name: str, asg_name: str, token: str, result: str) -> None:
    """Signal the ASG lifecycle hook to CONTINUE or ABANDON."""
    asg_client.complete_lifecycle_action(
        LifecycleHookName=hook_name,
        AutoScalingGroupName=asg_name,
        LifecycleActionToken=token,
        LifecycleActionResult=result,
    )
    logger.info("Lifecycle action completed with %s", result)


def lambda_handler(event, context):
    """
    Entry point.  EventBridge delivers the ASG lifecycle event as:
      event["detail"]["EC2InstanceId"]
      event["detail"]["LifecycleHookName"]
      event["detail"]["AutoScalingGroupName"]
      event["detail"]["LifecycleActionToken"]
    """
    logger.info("Event: %s", json.dumps(event))

    detail = event.get("detail", {})
    instance_id = detail["EC2InstanceId"]
    hook_name = detail["LifecycleHookName"]
    asg_name = detail["AutoScalingGroupName"]
    token = detail["LifecycleActionToken"]

    # ── Step 1: Wait for SSM agent to come online ──────────────────────────────
    agent_ready = wait_for_ssm_agent(instance_id)
    if not agent_ready:
        logger.error("SSM agent never came online for %s — ABANDON", instance_id)
        complete_lifecycle(hook_name, asg_name, token, "ABANDON")
        return {"statusCode": 500, "body": "SSM agent timeout"}

    # ── Step 2: Configure the instance ────────────────────────────────────────
    cmd_status = run_setup_commands(instance_id)

    # ── Step 3: Signal the lifecycle hook ─────────────────────────────────────
    lifecycle_result = "CONTINUE" if cmd_status == "Success" else "ABANDON"
    complete_lifecycle(hook_name, asg_name, token, lifecycle_result)

    return {"statusCode": 200, "body": f"SSM command status: {cmd_status}"}
