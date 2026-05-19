"""
Test assume-role with an inline session policy.

The session policy further restricts to S3+EC2 describe-only.
Demonstrates that session policies can only restrict, never expand, permissions.

Usage:
    python test_assume_role.py \
        --role-arn arn:aws:iam::123456789012:role/chikwex-assign18-developer-role \
        [--session-name my-test-session]
"""

import argparse
import json
import os
import sys
import boto3

SESSION_POLICY = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListAllMyBuckets",
                "s3:GetBucketLocation",
                "ec2:DescribeInstances",
                "ec2:DescribeVpcs",
            ],
            "Resource": "*",
        }
    ],
}

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"


def test_with_session(role_arn, session_name):
    sts = boto3.client("sts")

    print(f"\nAssuming role: {role_arn}")
    print(f"Session name : {session_name}")
    print(f"Session policy restricts to: s3:ListAllMyBuckets, ec2:DescribeInstances\n")

    resp = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=session_name,
        Policy=json.dumps(SESSION_POLICY),
        DurationSeconds=900,
    )

    creds = resp["Credentials"]
    assumed = boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        region_name="us-east-1",
    )

    results = []

    # Test 1: S3 list — should succeed (within both role policy and session policy)
    try:
        s3 = assumed.client("s3")
        s3.list_buckets()
        results.append(("s3:ListAllMyBuckets (should ALLOW)", True, True))
    except Exception as e:
        results.append(("s3:ListAllMyBuckets (should ALLOW)", True, False))

    # Test 2: EC2 describe — should succeed
    try:
        ec2 = assumed.client("ec2", region_name="us-east-1")
        ec2.describe_instances()
        results.append(("ec2:DescribeInstances (should ALLOW)", True, True))
    except Exception as e:
        results.append(("ec2:DescribeInstances (should ALLOW)", True, False))

    # Test 3: S3 delete — should fail (denied by both policies)
    try:
        s3 = assumed.client("s3")
        s3.delete_object(Bucket="any-bucket", Key="any-key")
        results.append(("s3:DeleteObject (should DENY)", False, True))
    except Exception:
        results.append(("s3:DeleteObject (should DENY)", False, False))

    # Test 4: EC2 RunInstances with t2.large — should fail
    try:
        ec2 = assumed.client("ec2", region_name="us-east-1")
        ec2.run_instances(
            ImageId="ami-00000000",
            InstanceType="t2.large",
            MinCount=1,
            MaxCount=1,
        )
        results.append(("ec2:RunInstances t2.large (should DENY)", False, True))
    except Exception:
        results.append(("ec2:RunInstances t2.large (should DENY)", False, False))

    print("=== Assume-Role + Session Policy Results ===\n")
    passed = 0
    failed = 0
    for label, expect_allow, got_allow in results:
        ok = (expect_allow == got_allow)
        status = PASS if ok else FAIL
        result_word = "ALLOWED" if got_allow else "DENIED"
        print(f"  [{status}] {label}  →  {result_word}")
        if ok:
            passed += 1
        else:
            failed += 1

    print(f"\nResults: {passed} passed, {failed} failed\n")
    return failed == 0


def main():
    parser = argparse.ArgumentParser(description="Assume role + session policy test")
    parser.add_argument("--role-arn", required=True)
    parser.add_argument("--session-name", default="assign18-session-test")
    args = parser.parse_args()

    success = test_with_session(args.role_arn, args.session_name)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
