"""
teardown.py – Remove all resources created by setup.py
Usage:  python teardown.py
"""

import boto3

REGION         = "us-east-1"
PREFIX         = "chikwex"
FUNCTION_NAME  = f"{PREFIX}-cw-demo"
ROLE_NAME      = f"{PREFIX}-cw-lambda-role"
SNS_TOPIC_NAME = f"{PREFIX}-cw-alarms"
LOG_GROUP      = f"/aws/lambda/{FUNCTION_NAME}"

iam  = boto3.client("iam",          region_name=REGION)
lam  = boto3.client("lambda",       region_name=REGION)
sns  = boto3.client("sns",          region_name=REGION)
logs = boto3.client("logs",         region_name=REGION)
cw   = boto3.client("cloudwatch",   region_name=REGION)
sts  = boto3.client("sts",          region_name=REGION)


def delete_alarms():
    names = [f"{PREFIX}-high-error-rate", f"{PREFIX}-high-response-time"]
    cw.delete_alarms(AlarmNames=names)
    print(f"[OK] Deleted alarms: {names}")


def delete_metric_filters():
    for name in [f"{PREFIX}-500-errors", f"{PREFIX}-slow-requests", f"{PREFIX}-response-time"]:
        try:
            logs.delete_metric_filter(logGroupName=LOG_GROUP, filterName=name)
            print(f"[OK] Deleted metric filter: {name}")
        except Exception as e:
            print(f"[--] {name}: {e}")


def delete_lambda():
    try:
        lam.delete_function(FunctionName=FUNCTION_NAME)
        print(f"[OK] Deleted Lambda: {FUNCTION_NAME}")
    except lam.exceptions.ResourceNotFoundException:
        print(f"[--] Lambda not found: {FUNCTION_NAME}")


def delete_log_group():
    try:
        logs.delete_log_group(logGroupName=LOG_GROUP)
        print(f"[OK] Deleted log group: {LOG_GROUP}")
    except logs.exceptions.ResourceNotFoundException:
        print(f"[--] Log group not found: {LOG_GROUP}")


def delete_sns():
    try:
        account = sts.get_caller_identity()["Account"]
        topic_arn = f"arn:aws:sns:{REGION}:{account}:{SNS_TOPIC_NAME}"
        # Unsubscribe all first
        subs = sns.list_subscriptions_by_topic(TopicArn=topic_arn)
        for sub in subs.get("Subscriptions", []):
            if sub["SubscriptionArn"] != "PendingConfirmation":
                sns.unsubscribe(SubscriptionArn=sub["SubscriptionArn"])
        sns.delete_topic(TopicArn=topic_arn)
        print(f"[OK] Deleted SNS topic: {topic_arn}")
    except Exception as e:
        print(f"[--] SNS: {e}")


def delete_role():
    try:
        policies = iam.list_attached_role_policies(RoleName=ROLE_NAME)["AttachedPolicies"]
        for p in policies:
            iam.detach_role_policy(RoleName=ROLE_NAME, PolicyArn=p["PolicyArn"])
        iam.delete_role(RoleName=ROLE_NAME)
        print(f"[OK] Deleted IAM role: {ROLE_NAME}")
    except iam.exceptions.NoSuchEntityException:
        print(f"[--] IAM role not found: {ROLE_NAME}")


def main():
    print("\n=== Teardown Assignment 12 ===\n")
    delete_alarms()
    delete_metric_filters()
    delete_lambda()
    delete_log_group()
    delete_sns()
    delete_role()
    print("\n=== Teardown Complete ===")


if __name__ == "__main__":
    main()
