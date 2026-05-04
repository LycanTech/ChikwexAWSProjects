"""
EventBridge rule: every hour
- Find all security groups that allow inbound 0.0.0.0/0 on port 22
- Publish an alert to SNS listing each offending SG
"""

import os
import json
import boto3
from datetime import datetime, timezone

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def _is_risky(permission: dict) -> bool:
    """Return True if the permission allows SSH from any IPv4 address."""
    if permission.get("IpProtocol") not in ("tcp", "-1"):
        return False

    from_port = permission.get("FromPort", 0)
    to_port = permission.get("ToPort", 65535)

    # Protocol -1 means all traffic – that includes port 22
    if permission.get("IpProtocol") == "-1":
        port_match = True
    else:
        port_match = from_port <= 22 <= to_port

    if not port_match:
        return False

    for ip_range in permission.get("IpRanges", []):
        if ip_range.get("CidrIp") == "0.0.0.0/0":
            return True

    return False


def handler(event, context):
    now = datetime.now(timezone.utc)

    paginator = ec2.get_paginator("describe_security_groups")
    pages = paginator.paginate()

    risky_groups = []

    for page in pages:
        for sg in page["SecurityGroups"]:
            for permission in sg.get("IpPermissions", []):
                if _is_risky(permission):
                    risky_groups.append(
                        {
                            "group_id": sg["GroupId"],
                            "group_name": sg["GroupName"],
                            "vpc_id": sg.get("VpcId", ""),
                            "description": sg.get("Description", ""),
                        }
                    )
                    break  # one match per SG is enough

    report = {
        "timestamp": now.isoformat(),
        "risky_sg_count": len(risky_groups),
        "risky_security_groups": risky_groups,
        "alert": len(risky_groups) > 0,
    }

    subject = (
        f"ALERT: {len(risky_groups)} Security Group(s) expose SSH to 0.0.0.0/0"
        if risky_groups
        else f"Security Check OK – {now.strftime('%Y-%m-%d %H:%M UTC')}"
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject,
        Message=json.dumps(report, indent=2),
    )

    print(json.dumps(report))
    return report
