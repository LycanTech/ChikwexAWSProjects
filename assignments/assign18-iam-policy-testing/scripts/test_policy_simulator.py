"""
IAM Policy Simulator tests for developer-test user.
Validates each permission rule defined in the assignment:
  - Can list S3 buckets
  - Cannot delete S3 objects
  - Can launch t2.micro instance
  - Cannot launch t2.large instance

Usage:
    python test_policy_simulator.py \
        --policy-arn arn:aws:iam::123456789012:policy/chikwex-assign18-developer-policy \
        --boundary-arn arn:aws:iam::123456789012:policy/chikwex-assign18-permission-boundary
"""

import argparse
import json
import sys
import boto3

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"


def simulate(iam, policy_source_arn, policy_arns, action, resource, context_entries=None):
    kwargs = {
        "PolicySourceArn": policy_source_arn,
        "PolicyInputList": [],
        "ActionNames": [action],
        "ResourceArns": [resource],
    }
    if policy_arns:
        kwargs["PolicyInputList"] = [
            open_policy(iam, arn) for arn in policy_arns
        ]
    if context_entries:
        kwargs["ContextEntries"] = context_entries

    resp = iam.simulate_custom_policy(
        PolicyInputList=kwargs["PolicyInputList"],
        ActionNames=[action],
        ResourceArns=[resource],
        ContextEntries=context_entries or [],
    )
    decision = resp["EvaluationResults"][0]["EvalDecision"]
    return decision


def open_policy(iam, arn):
    resp = iam.get_policy(PolicyArn=arn)
    version_id = resp["Policy"]["DefaultVersionId"]
    doc = iam.get_policy_version(PolicyArn=arn, VersionId=version_id)
    return json.dumps(doc["PolicyVersion"]["Document"])


def run_tests(policy_arn, boundary_arn):
    iam = boto3.client("iam")

    def get_doc(arn):
        return open_policy(iam, arn)

    policies = [get_doc(policy_arn)]
    if boundary_arn:
        policies.append(get_doc(boundary_arn))

    tests = [
        {
            "name": "Can list S3 buckets",
            "action": "s3:ListAllMyBuckets",
            "resource": "*",
            "context": [],
            "expected": "allowed",
        },
        {
            "name": "Cannot delete S3 objects",
            "action": "s3:DeleteObject",
            "resource": "arn:aws:s3:::any-bucket/any-key",
            "context": [{"ContextKeyName": "aws:ResourceTag/Team", "ContextKeyValues": ["Dev"], "ContextKeyType": "string"}],
            "expected": "explicitDeny",
        },
        {
            "name": "Can launch t2.micro instance",
            "action": "ec2:RunInstances",
            "resource": "arn:aws:ec2:us-east-1::instance/*",
            "context": [{"ContextKeyName": "ec2:InstanceType", "ContextKeyValues": ["t2.micro"], "ContextKeyType": "string"}],
            "expected": "allowed",
        },
        {
            "name": "Cannot launch t2.large instance",
            "action": "ec2:RunInstances",
            "resource": "arn:aws:ec2:us-east-1::instance/*",
            "context": [{"ContextKeyName": "ec2:InstanceType", "ContextKeyValues": ["t2.large"], "ContextKeyType": "string"}],
            "expected": "implicitDeny",
        },
        {
            "name": "Cannot access production-tagged resource",
            "action": "s3:GetObject",
            "resource": "arn:aws:s3:::prod-bucket/file.txt",
            "context": [{"ContextKeyName": "aws:ResourceTag/Environment", "ContextKeyValues": ["production"], "ContextKeyType": "string"}],
            "expected": "explicitDeny",
        },
        {
            "name": "S3 read allowed on Team:Dev tagged bucket",
            "action": "s3:GetObject",
            "resource": "arn:aws:s3:::dev-data-bucket/report.csv",
            "context": [{"ContextKeyName": "aws:ResourceTag/Team", "ContextKeyValues": ["Dev"], "ContextKeyType": "string"}],
            "expected": "allowed",
        },
    ]

    passed = 0
    failed = 0

    print("\n=== IAM Policy Simulator Results ===\n")
    for t in tests:
        resp = iam.simulate_custom_policy(
            PolicyInputList=policies,
            ActionNames=[t["action"]],
            ResourceArns=[t["resource"]],
            ContextEntries=t["context"],
        )
        decision = resp["EvaluationResults"][0]["EvalDecision"]
        ok = decision == t["expected"]
        status = PASS if ok else FAIL
        print(f"  [{status}] {t['name']}")
        print(f"         action={t['action']}  expected={t['expected']}  got={decision}")
        if ok:
            passed += 1
        else:
            failed += 1

    print(f"\nResults: {passed} passed, {failed} failed\n")
    return failed == 0


def main():
    parser = argparse.ArgumentParser(description="IAM Policy Simulator tests")
    parser.add_argument("--policy-arn", required=True, help="ARN of the developer policy")
    parser.add_argument("--boundary-arn", default=None, help="ARN of the permission boundary policy (optional)")
    args = parser.parse_args()

    success = run_tests(args.policy_arn, args.boundary_arn)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
