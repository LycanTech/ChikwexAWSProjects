import boto3
import uuid
import random
import time
from decimal import Decimal

dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
table = dynamodb.Table("Orders")

CUSTOMERS = [f"customer-{i}" for i in range(1, 11)]  # 10 unique customers
STATUSES = ["PENDING", "COMPLETE", "CANCELLED", "PROCESSING"]

def lambda_handler(event, context):
    inserted = 0
    expires_at = int(time.time()) + 604800  # 7 days from now (TTL)

    with table.batch_writer() as batch:
        for _ in range(50):
            order = {
                "orderId":    str(uuid.uuid4()),
                "customerId": random.choice(CUSTOMERS),
                "amount":     Decimal(str(round(random.uniform(10.0, 500.0), 2))),
                "status":     random.choice(STATUSES),
                "timestamp":  int(time.time()),
                "expiresAt":  expires_at,
            }
            batch.put_item(Item=order)
            inserted += 1

    print(f"Inserted {inserted} orders into Orders table.")
    return {"statusCode": 200, "body": f"Inserted {inserted} orders."}
