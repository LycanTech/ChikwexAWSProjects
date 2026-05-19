"""
Query IAM Access Analyzer for active findings in the account.

Lists all ACTIVE findings from the account-level analyzer provisioned by Terraform.
Prints a summary and exits non-zero if any public-access findings are found.

Usage:
    python run_access_analyzer.py \
        --analyzer-arn arn:aws:access-analyzer:us-east-1:123456789012:analyzer/chikwex-assign18-account-analyzer \
        [--region us-east-1]
"""

import argparse
import sys
import boto3
from botocore.exceptions import ClientError


PASS = "\033[32mPASS\033[0m"
WARN = "\033[33mWARN\033[0m"
FAIL = "\033[31mFAIL\033[0m"


def run_analyzer_check(analyzer_arn, region):
    client = boto3.client("accessanalyzer", region_name=region)

    print(f"\n=== Access Analyzer Findings ===")
    print(f"Analyzer : {analyzer_arn}\n")

    paginator = client.get_paginator("list_findings")
    pages = paginator.paginate(
        analyzerArn=analyzer_arn,
        filter={"status": {"eq": ["ACTIVE"]}},
    )

    findings = []
    for page in pages:
        findings.extend(page.get("findings", []))

    public_access_findings = [
        f for f in findings
        if f.get("isPublic", False)
    ]

    if not findings:
        print(f"  [{PASS}] No active findings — account has no public external access")
    else:
        print(f"  Total active findings : {len(findings)}")
        print(f"  Public-access findings: {len(public_access_findings)}\n")

        for f in findings:
            is_public = f.get("isPublic", False)
            status_icon = FAIL if is_public else WARN
            rtype = f.get("resourceType", "unknown")
            resource = f.get("resource", "unknown")
            finding_type = f.get("findingType", "unknown")
            print(f"  [{status_icon}] {rtype}")
            print(f"         Resource  : {resource}")
            print(f"         Type      : {finding_type}")
            print(f"         Public    : {is_public}")
            print()

    if public_access_findings:
        print(f"\n  [{FAIL}] {len(public_access_findings)} public-access finding(s) found — review and archive or remediate\n")
        return False

    print(f"\n  [{PASS}] Access Analyzer shows no public access findings\n")
    return True


def check_policy_validation(policy_arn, region):
    """Run AWS Access Analyzer policy validation on the developer policy."""
    iam = boto3.client("iam", region_name=region)
    client = boto3.client("accessanalyzer", region_name=region)

    resp = iam.get_policy(PolicyArn=policy_arn)
    version_id = resp["Policy"]["DefaultVersionId"]
    doc = iam.get_policy_version(PolicyArn=policy_arn, VersionId=version_id)
    import json
    policy_doc = json.dumps(doc["PolicyVersion"]["Document"])

    print(f"=== Policy Validation ({policy_arn.split('/')[-1]}) ===\n")
    val_resp = client.validate_policy(
        policyDocument=policy_doc,
        policyType="IDENTITY_POLICY",
    )

    findings = val_resp.get("findings", [])
    if not findings:
        print(f"  [{PASS}] No policy validation findings — policy is well-formed\n")
        return True

    errors = [f for f in findings if f["findingType"] == "ERROR"]
    warnings = [f for f in findings if f["findingType"] == "WARNING"]
    suggestions = [f for f in findings if f["findingType"] == "SUGGESTION"]

    for f in findings:
        icon = FAIL if f["findingType"] == "ERROR" else WARN
        print(f"  [{icon}] [{f['findingType']}] {f['findingDetails']}")
        if "locations" in f and f["locations"]:
            loc = f["locations"][0]
            print(f"         Path: {loc.get('path', [])}")
        print()

    print(f"  Errors: {len(errors)}  Warnings: {len(warnings)}  Suggestions: {len(suggestions)}\n")
    return len(errors) == 0


def main():
    parser = argparse.ArgumentParser(description="Access Analyzer findings check")
    parser.add_argument("--analyzer-arn", required=True)
    parser.add_argument("--policy-arn", default=None, help="Run policy validation on this policy ARN")
    parser.add_argument("--region", default="us-east-1")
    args = parser.parse_args()

    findings_ok = run_analyzer_check(args.analyzer_arn, args.region)

    policy_ok = True
    if args.policy_arn:
        policy_ok = check_policy_validation(args.policy_arn, args.region)

    sys.exit(0 if (findings_ok and policy_ok) else 1)


if __name__ == "__main__":
    main()
