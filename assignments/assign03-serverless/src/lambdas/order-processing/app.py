import json
import os
import random
from datetime import datetime
from decimal import Decimal
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK for X-Ray tracing
patch_all()

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
ORDERS_TABLE = os.environ['ORDERS_TABLE']
ORDER_TOPIC_ARN = os.environ['ORDER_TOPIC_ARN']

# Get table reference
orders_table = dynamodb.Table(ORDERS_TABLE)


class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert Decimal objects to float for JSON serialization"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)


@xray_recorder.capture('simulate_payment_processing')
def process_payment(order_data):
    """
    Simulates payment processing
    In production, this would integrate with a payment gateway (Stripe, PayPal, etc.)

    Args:
        order_data: Dictionary containing order information

    Returns:
        dict: Payment result with status and paymentId
    """
    # Simulate payment processing delay
    import time
    time.sleep(0.5)

    # Simulate 95% success rate
    success = random.random() < 0.95

    if success:
        payment_id = f"PAY-{random.randint(100000, 999999)}"
        return {
            'status': 'success',
            'paymentId': payment_id,
            'amount': float(order_data.get('totalAmount', {}).get('N', 0))
        }
    else:
        return {
            'status': 'failed',
            'error': 'Payment declined'
        }


@xray_recorder.capture('simulate_inventory_update')
def update_inventory(items):
    """
    Simulates inventory update
    In production, this would update an inventory management system

    Args:
        items: List of items to update in inventory

    Returns:
        dict: Inventory update result
    """
    # Simulate inventory check delay
    import time
    time.sleep(0.3)

    # Simulate 98% success rate
    success = random.random() < 0.98

    if success:
        return {
            'status': 'success',
            'itemsUpdated': len(items)
        }
    else:
        return {
            'status': 'failed',
            'error': 'Insufficient inventory'
        }


@xray_recorder.capture('refund_payment')
def refund_payment(payment_id):
    """
    Simulates payment refund (compensating transaction)

    Args:
        payment_id: The payment ID to refund

    Returns:
        dict: Refund result
    """
    # Simulate refund processing
    import time
    time.sleep(0.5)

    refund_id = f"REF-{random.randint(100000, 999999)}"
    return {
        'status': 'success',
        'refundId': refund_id,
        'originalPaymentId': payment_id
    }


@xray_recorder.capture('update_order_status')
def update_order_status(order_id, created_at, status):
    """
    Updates the order status in DynamoDB

    Args:
        order_id: The order ID
        created_at: The creation timestamp
        status: New status

    Returns:
        dict: Update result
    """
    try:
        response = orders_table.update_item(
            Key={
                'orderId': order_id,
                'createdAt': created_at
            },
            UpdateExpression='SET #status = :status, #updatedAt = :updatedAt',
            ExpressionAttributeNames={
                '#status': 'status',
                '#updatedAt': 'updatedAt'
            },
            ExpressionAttributeValues={
                ':status': status,
                ':updatedAt': datetime.utcnow().isoformat()
            },
            ReturnValues='ALL_NEW'
        )
        return response.get('Attributes', {})

    except Exception as e:
        print(f"Error updating order status: {str(e)}")
        raise


def lambda_handler(event, context):
    """
    Lambda handler for order processing
    Processes orders from SQS queue or direct invocations from Step Functions

    Args:
        event: SQS event or direct invocation event
        context: Lambda context

    Returns:
        dict: Processing result
    """
    try:
        # Check if this is from Step Functions (direct invocation)
        if 'action' in event:
            action = event['action']

            if action == 'processPayment':
                # Process payment
                order_data = event.get('orderData', {})
                payment_result = process_payment(order_data)

                # Publish metric
                cloudwatch.put_metric_data(
                    Namespace='OrderProcessingSystem',
                    MetricData=[
                        {
                            'MetricName': 'PaymentsProcessed',
                            'Value': 1,
                            'Unit': 'Count',
                            'Dimensions': [
                                {
                                    'Name': 'Status',
                                    'Value': payment_result['status']
                                }
                            ]
                        }
                    ]
                )

                return payment_result

            elif action == 'updateInventory':
                # Update inventory
                items = event.get('items', [])
                inventory_result = update_inventory(items)

                # Publish metric
                cloudwatch.put_metric_data(
                    Namespace='OrderProcessingSystem',
                    MetricData=[
                        {
                            'MetricName': 'InventoryUpdates',
                            'Value': 1,
                            'Unit': 'Count',
                            'Dimensions': [
                                {
                                    'Name': 'Status',
                                    'Value': inventory_result['status']
                                }
                            ]
                        }
                    ]
                )

                return inventory_result

            elif action == 'refundPayment':
                # Refund payment (compensating transaction)
                payment_id = event.get('paymentId')
                refund_result = refund_payment(payment_id)

                # Publish metric
                cloudwatch.put_metric_data(
                    Namespace='OrderProcessingSystem',
                    MetricData=[
                        {
                            'MetricName': 'PaymentRefunds',
                            'Value': 1,
                            'Unit': 'Count'
                        }
                    ]
                )

                return refund_result

        # Handle SQS batch processing
        elif 'Records' in event:
            results = []

            for record in event['Records']:
                try:
                    # Parse message body
                    message = json.loads(record['body'])
                    order_id = message['orderId']
                    created_at = message['createdAt']

                    print(f"Processing order: {order_id}")

                    # Update order status to PROCESSING
                    with xray_recorder.capture('update_to_processing'):
                        update_order_status(order_id, created_at, 'PROCESSING')

                    # Simulate order processing
                    # In production, this would trigger the Step Functions workflow
                    # For now, we'll just mark it as processed

                    # Send notification to SNS
                    with xray_recorder.capture('sns_publish'):
                        sns.publish(
                            TopicArn=ORDER_TOPIC_ARN,
                            Subject='Order Processing Started',
                            Message=json.dumps({
                                'orderId': order_id,
                                'status': 'PROCESSING',
                                'message': f'Order {order_id} is being processed'
                            }, cls=DecimalEncoder)
                        )

                    results.append({
                        'orderId': order_id,
                        'status': 'success'
                    })

                    # Publish metric
                    cloudwatch.put_metric_data(
                        Namespace='OrderProcessingSystem',
                        MetricData=[
                            {
                                'MetricName': 'OrdersProcessed',
                                'Value': 1,
                                'Unit': 'Count'
                            }
                        ]
                    )

                except Exception as e:
                    print(f"Error processing record: {str(e)}")
                    results.append({
                        'orderId': message.get('orderId', 'unknown'),
                        'status': 'failed',
                        'error': str(e)
                    })

                    # Publish error metric
                    cloudwatch.put_metric_data(
                        Namespace='OrderProcessingSystem',
                        MetricData=[
                            {
                                'MetricName': 'OrderProcessingErrors',
                                'Value': 1,
                                'Unit': 'Count'
                            }
                        ]
                    )

            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Batch processed',
                    'results': results
                })
            }

        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid event format'
                })
            }

    except Exception as e:
        print(f"Error in order processing: {str(e)}")

        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalServerError',
                'message': str(e)
            })
        }
