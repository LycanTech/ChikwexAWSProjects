"""
invoke.py – Invoke the Lambda 100 times and report outcomes.
Usage:  python invoke.py
"""

import boto3
import json
import time
from collections import Counter

REGION        = "us-east-1"
PREFIX        = "chikwex"
FUNCTION_NAME = f"{PREFIX}-cw-demo"
INVOCATIONS   = 100

lam = boto3.client("lambda", region_name=REGION)


def invoke_once(i):
    resp = lam.invoke(
        FunctionName=FUNCTION_NAME,
        InvocationType="RequestResponse",
        Payload=json.dumps({"invocation": i})
    )
    payload = json.loads(resp["Payload"].read())
    status  = resp["StatusCode"]          # HTTP wrapper (always 200 if Lambda ran)
    code    = payload.get("statusCode")   # our app status code
    return code


def main():
    print(f"Invoking {FUNCTION_NAME} × {INVOCATIONS} ...\n")
    results = Counter()

    for i in range(1, INVOCATIONS + 1):
        code = invoke_once(i)
        results[code] += 1

        # Progress indicator every 10 calls
        if i % 10 == 0:
            print(f"  [{i:>3}/{INVOCATIONS}] running totals: {dict(results)}")

        # Small delay to spread logs across time (helps Insights queries)
        time.sleep(0.3)

    print("\n=== Final Results ===")
    total   = sum(results.values())
    success = results.get(200, 0)
    errors  = total - success
    print(f"  Total invocations : {total}")
    print(f"  Successful (2xx)  : {success}  ({success/total*100:.1f}%)")
    print(f"  Errors            : {errors}   ({errors/total*100:.1f}%)")
    print(f"\nStatus code breakdown: {dict(results)}")
    print("\nLogs will appear in CloudWatch within ~30 seconds.")
    print(f"Log group: /aws/lambda/{FUNCTION_NAME}")


if __name__ == "__main__":
    main()
