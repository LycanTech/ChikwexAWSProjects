import boto3
from decimal import Decimal

dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
stats_table = dynamodb.Table("CustomerStats")

def lambda_handler(event, context):
    for record in event["Records"]:
        # Only process new INSERT events
        if record["eventName"] != "INSERT":
            continue

        new_image = record["dynamodb"].get("NewImage", {})

        customer_id = new_image.get("customerId", {}).get("S")
        amount_str  = new_image.get("amount", {}).get("N")

        if not customer_id or amount_str is None:
            print(f"Skipping record — missing customerId or amount: {new_image}")
            continue

        amount = Decimal(amount_str)

        # Atomic counter update — safe for concurrent Lambda invocations
        stats_table.update_item(
            Key={"customerId": customer_id},
            UpdateExpression="ADD totalSales :amount, orderCount :one",
            ExpressionAttributeValues={
                ":amount": amount,
                ":one":    Decimal(1),
            },
        )

        print(f"Updated stats for {customer_id}: +{amount}")

    return {"statusCode": 200}
