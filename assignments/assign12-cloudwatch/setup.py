"""
setup.py  –  One-shot provisioning for Assignment 12
Builds: IAM role, Lambda, SNS topic, Metric Filters, CloudWatch Alarms
Usage:  python setup.py --email your@email.com
"""

import boto3
import json
import zipfile
import io
import time
import argparse

# ─── Config ──────────────────────────────────────────────────────────────────
REGION         = "us-east-1"
PREFIX         = "chikwex"
FUNCTION_NAME  = f"{PREFIX}-cw-demo"
ROLE_NAME      = f"{PREFIX}-cw-lambda-role"
SNS_TOPIC_NAME = f"{PREFIX}-cw-alarms"
LOG_GROUP      = f"/aws/lambda/{FUNCTION_NAME}"

# ─── Clients ─────────────────────────────────────────────────────────────────
iam    = boto3.client("iam",    region_name=REGION)
lam    = boto3.client("lambda", region_name=REGION)
sns    = boto3.client("sns",    region_name=REGION)
logs   = boto3.client("logs",   region_name=REGION)
cw     = boto3.client("cloudwatch", region_name=REGION)
sts    = boto3.client("sts",    region_name=REGION)


# ─── Helpers ─────────────────────────────────────────────────────────────────
def get_account_id():
    return sts.get_caller_identity()["Account"]


def zip_lambda():
    """Package lambda_function.py into an in-memory zip."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write("lambda_function.py")
    buf.seek(0)
    return buf.read()


# ─── 1. IAM Role ─────────────────────────────────────────────────────────────
def create_role():
    trust = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect":    "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action":    "sts:AssumeRole"
        }]
    }
    try:
        role = iam.create_role(
            RoleName=ROLE_NAME,
            AssumeRolePolicyDocument=json.dumps(trust),
            Description="Lambda execution role for CW assignment"
        )
        iam.attach_role_policy(
            RoleName=ROLE_NAME,
            PolicyArn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        )
        role_arn = role["Role"]["Arn"]
        print(f"[OK] Created IAM role: {role_arn}")
        time.sleep(10)  # IAM propagation delay
    except iam.exceptions.EntityAlreadyExistsException:
        role_arn = iam.get_role(RoleName=ROLE_NAME)["Role"]["Arn"]
        print(f"[OK] IAM role already exists: {role_arn}")
    return role_arn


# ─── 2. Lambda ───────────────────────────────────────────────────────────────
def create_lambda(role_arn):
    code = zip_lambda()
    try:
        fn = lam.create_function(
            FunctionName=FUNCTION_NAME,
            Runtime="python3.12",
            Role=role_arn,
            Handler="lambda_function.lambda_handler",
            Code={"ZipFile": code},
            Timeout=10,
            MemorySize=128,
            Description="CW assignment – generates INFO/WARN/ERROR logs"
        )
        fn_arn = fn["FunctionArn"]
        print(f"[OK] Created Lambda: {fn_arn}")
        # Wait until Active
        waiter = lam.get_waiter("function_active")
        waiter.wait(FunctionName=FUNCTION_NAME)
    except lam.exceptions.ResourceConflictException:
        # Update code if already exists
        lam.update_function_code(FunctionName=FUNCTION_NAME, ZipFile=code)
        fn_arn = lam.get_function(FunctionName=FUNCTION_NAME)["Configuration"]["FunctionArn"]
        print(f"[OK] Lambda already exists (code updated): {fn_arn}")
    return fn_arn


# ─── 3. SNS Topic + Email Subscription ───────────────────────────────────────
def create_sns(email):
    topic_arn = sns.create_topic(Name=SNS_TOPIC_NAME)["TopicArn"]
    print(f"[OK] SNS topic: {topic_arn}")

    sns.subscribe(
        TopicArn=topic_arn,
        Protocol="email",
        Endpoint=email
    )
    print(f"[!!] Subscription confirmation email sent to {email} – check your inbox and CONFIRM before alarms fire!")
    return topic_arn


# ─── 4a. Ensure log group exists ─────────────────────────────────────────────
def ensure_log_group():
    """
    Lambda auto-creates its log group on first invocation, but we need it
    to exist NOW so metric filters can be attached before any invocations run.
    """
    try:
        logs.create_log_group(logGroupName=LOG_GROUP)
        print(f"[OK] Created log group: {LOG_GROUP}")
    except logs.exceptions.ResourceAlreadyExistsException:
        print(f"[OK] Log group already exists: {LOG_GROUP}")


# ─── 4b. Metric Filters ──────────────────────────────────────────────────────
def create_metric_filters():
    """
    Three metric filters on the Lambda log group:
      a) Count of 500 errors
      b) Count of slow requests  (WARN level)
      c) Response time value      (extracted from every log line)
    """

    filters = [
        {
            "name":      f"{PREFIX}-500-errors",
            "pattern":   '{ $.error_code = 500 }',
            "metric":    "HTTP500ErrorCount",
            "namespace": f"{PREFIX}/AppMetrics",
            "value":     "1",
            "unit":      "Count",
            "desc":      "Count of HTTP 500 errors"
        },
        {
            "name":      f"{PREFIX}-slow-requests",
            "pattern":   '{ $.level = "WARN" }',
            "metric":    "SlowRequestCount",
            "namespace": f"{PREFIX}/AppMetrics",
            "value":     "1",
            "unit":      "Count",
            "desc":      "Count of slow requests (>500ms)"
        },
        {
            "name":      f"{PREFIX}-response-time",
            "pattern":   '{ $.response_time > 0 }',
            "metric":    "ResponseTime",
            "namespace": f"{PREFIX}/AppMetrics",
            "value":     "$.response_time",  # extract the actual value
            "unit":      "Milliseconds",
            "desc":      "Response time in milliseconds"
        },
    ]

    for f in filters:
        logs.put_metric_filter(
            logGroupName=LOG_GROUP,
            filterName=f["name"],
            filterPattern=f["pattern"],
            metricTransformations=[{
                "metricName":      f["metric"],
                "metricNamespace": f["namespace"],
                "metricValue":     f["value"],
                "unit":            f["unit"]
            }]
        )
        print(f"[OK] Metric filter '{f['name']}': {f['desc']}")


# ─── 5. CloudWatch Alarms ─────────────────────────────────────────────────────
def create_alarms(topic_arn):
    namespace = f"{PREFIX}/AppMetrics"

    # Alarm 1 – High error rate (>5% in 5 min)
    # We use a Math expression: errors / total_invocations * 100 > 5
    # Simpler approach: absolute ERROR count > 3 in a 5-minute window
    # (5% of ~expected 20 invocations/5min ≈ 1, but we use 3 to avoid noise)
    cw.put_metric_alarm(
        AlarmName=f"{PREFIX}-high-error-rate",
        AlarmDescription="Error rate > 5% – too many failed requests in 5 minutes",
        Namespace=namespace,
        MetricName="HTTP500ErrorCount",
        Statistic="Sum",
        Period=300,           # 5 minutes
        EvaluationPeriods=1,
        Threshold=3,          # >3 500-errors in 5 min → alarm
        ComparisonOperator="GreaterThanThreshold",
        TreatMissingData="notBreaching",
        AlarmActions=[topic_arn],
        OKActions=[topic_arn],
        Unit="Count"
    )
    print(f"[OK] Alarm: {PREFIX}-high-error-rate  (HTTP500Count > 3 in 5 min)")

    # Alarm 2 – High average response time (>1000ms)
    cw.put_metric_alarm(
        AlarmName=f"{PREFIX}-high-response-time",
        AlarmDescription="Average response time > 1000ms",
        Namespace=namespace,
        MetricName="ResponseTime",
        Statistic="Average",
        Period=300,           # 5 minutes
        EvaluationPeriods=1,
        Threshold=1000,       # ms
        ComparisonOperator="GreaterThanThreshold",
        TreatMissingData="notBreaching",
        AlarmActions=[topic_arn],
        OKActions=[topic_arn],
        Unit="Milliseconds"
    )
    print(f"[OK] Alarm: {PREFIX}-high-response-time  (AvgResponseTime > 1000ms in 5 min)")


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--email", required=True, help="Email address for alarm notifications")
    args = parser.parse_args()

    print("\n=== Assignment 12 Setup ===\n")
    role_arn  = create_role()
    fn_arn    = create_lambda(role_arn)
    topic_arn = create_sns(args.email)
    ensure_log_group()
    create_metric_filters()
    create_alarms(topic_arn)

    print("\n=== Setup Complete ===")
    print(f"  Lambda ARN : {fn_arn}")
    print(f"  SNS Topic  : {topic_arn}")
    print(f"  Log Group  : {LOG_GROUP}")
    print("\nNext step: python invoke.py")


if __name__ == "__main__":
    main()
