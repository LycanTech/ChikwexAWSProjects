"""
EventBridge rule: every 5 minutes
- Find EC2 instances tagged Environment=Dev
- Stop  running instances if current hour >= 18 (6 pm UTC)
- Start stopped instances if current hour == 9  (9 am UTC)
- Publish a summary report to SNS
"""

import os
import json
import boto3
from datetime import datetime, timezone

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def handler(event, context):
    now = datetime.now(timezone.utc)
    current_hour = now.hour

    # Discover all Dev instances
    paginator = ec2.get_paginator("describe_instances")
    pages = paginator.paginate(
        Filters=[{"Name": "tag:Environment", "Values": ["Dev"]}]
    )

    running_ids = []
    stopped_ids = []

    for page in pages:
        for reservation in page["Reservations"]:
            for inst in reservation["Instances"]:
                state = inst["State"]["Name"]
                iid = inst["InstanceId"]
                if state == "running":
                    running_ids.append(iid)
                elif state == "stopped":
                    stopped_ids.append(iid)

    started = []
    stopped = []

    # Start at 9 am
    if current_hour == 9 and stopped_ids:
        ec2.start_instances(InstanceIds=stopped_ids)
        started = stopped_ids

    # Stop at / after 6 pm
    if current_hour >= 18 and running_ids:
        ec2.stop_instances(InstanceIds=running_ids)
        stopped = running_ids

    # Build report
    report = {
        "timestamp": now.isoformat(),
        "current_hour_utc": current_hour,
        "action": "start" if started else ("stop" if stopped else "none"),
        "instances_started": started,
        "instances_stopped": stopped,
        "running_found": len(running_ids),
        "stopped_found": len(stopped_ids),
    }

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"EC2 Scheduler Report – {now.strftime('%Y-%m-%d %H:%M UTC')}",
        Message=json.dumps(report, indent=2),
    )

    print(json.dumps(report))
    return report
