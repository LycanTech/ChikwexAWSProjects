"""
EventBridge rule: every Sunday at 2 am UTC
- Find all EBS snapshots owned by this account
- Delete snapshots that are BOTH older than 30 days AND have no tags
- Publish a summary report to SNS
"""

import os
import json
import boto3
from datetime import datetime, timezone, timedelta

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "30"))


def handler(event, context):
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=RETENTION_DAYS)

    paginator = ec2.get_paginator("describe_snapshots")
    pages = paginator.paginate(OwnerIds=["self"])

    deleted = []
    skipped = []
    errors = []

    for page in pages:
        for snap in page["Snapshots"]:
            snap_id = snap["SnapshotId"]
            start_time = snap["StartTime"]

            # Only consider snapshots older than retention window
            if start_time > cutoff:
                skipped.append(snap_id)
                continue

            # Only delete untagged snapshots
            tags = snap.get("Tags") or []
            if tags:
                skipped.append(snap_id)
                continue

            try:
                ec2.delete_snapshot(SnapshotId=snap_id)
                deleted.append(snap_id)
                print(f"Deleted snapshot {snap_id} (created {start_time.isoformat()})")
            except ec2.exceptions.ClientError as exc:
                errors.append({"snapshot_id": snap_id, "error": str(exc)})
                print(f"Failed to delete {snap_id}: {exc}")

    report = {
        "timestamp": now.isoformat(),
        "retention_days": RETENTION_DAYS,
        "deleted_count": len(deleted),
        "skipped_count": len(skipped),
        "error_count": len(errors),
        "deleted_snapshots": deleted,
        "errors": errors,
    }

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"Weekly Snapshot Cleanup Report – {now.strftime('%Y-%m-%d')}",
        Message=json.dumps(report, indent=2),
    )

    print(json.dumps(report))
    return report
