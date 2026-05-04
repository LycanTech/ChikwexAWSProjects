import json
import os
import uuid
from datetime import datetime
from decimal import Decimal
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK for X-Ray tracing
patch_all()

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
ORDERS_TABLE = os.environ['ORDERS_TABLE']
ORDER_QUEUE_URL = os.environ['ORDER_QUEUE_URL']

# Get table reference
orders_table = dynamodb.Table(ORDERS_TABLE)


class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert Decimal objects to float for JSON serialization"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)


def validate_order(order_data):
    """
    Validates the order data structure and required fields

    Args:
        order_data: Dictionary containing order information

    Returns:
        tuple: (is_valid: bool, error_message: str or None)
    """
    required_fields = ['customerId', 'items']

    # Check required fields
    for field in required_fields:
        if field not in order_data:
            return False, f"Missing required field: {field}"

    # Validate items
    if not isinstance(order_data['items'], list) or len(order_data['items']) == 0:
        return False, "Items must be a non-empty array"

    # Validate each item
    for idx, item in enumerate(order_data['items']):
        if 'productId' not in item:
            return False, f"Item {idx} missing productId"
        if 'quantity' not in item or item['quantity'] <= 0:
            return False, f"Item {idx} must have positive quantity"
        if 'price' not in item or item['price'] <= 0:
            return False, f"Item {idx} must have positive price"

    return True, None


def calculate_total(items):
    """
    Calculates the total order amount

    Args:
        items: List of order items with quantity and price

    Returns:
        Decimal: Total order amount
    """
    total = Decimal('0')
    for item in items:
        total += Decimal(str(item['quantity'])) * Decimal(str(item['price']))
    return total


@xray_recorder.capture('create_order')
def lambda_handler(event, context):
    """
    Lambda handler for order creation
    Validates order, saves to DynamoDB, and sends to SQS for processing

    Args:
        event: API Gateway event containing order data
        context: Lambda context

    Returns:
        dict: API Gateway response with status code and body
    """
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))

        # Validate order data
        is_valid, error_message = validate_order(body)
        if not is_valid:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'ValidationError',
                    'message': error_message
                })
            }

        # Generate order ID and timestamp
        order_id = str(uuid.uuid4())
        created_at = datetime.utcnow().isoformat()

        # Calculate total
        total_amount = calculate_total(body['items'])

        # Create order object
        order = {
            'orderId': order_id,
            'createdAt': created_at,
            'customerId': body['customerId'],
            'items': body['items'],
            'totalAmount': total_amount,
            'status': 'PENDING',
            'updatedAt': created_at,
            'customerEmail': body.get('customerEmail', ''),
            'shippingAddress': body.get('shippingAddress', {})
        }

        # Save to DynamoDB
        with xray_recorder.capture('dynamodb_put_item'):
            orders_table.put_item(Item=order)

        # Send message to SQS for processing
        with xray_recorder.capture('sqs_send_message'):
            sqs.send_message(
                QueueUrl=ORDER_QUEUE_URL,
                MessageBody=json.dumps({
                    'orderId': order_id,
                    'createdAt': created_at,
                    'customerId': body['customerId'],
                    'totalAmount': float(total_amount)
                }, cls=DecimalEncoder),
                MessageAttributes={
                    'orderType': {
                        'StringValue': 'standard',
                        'DataType': 'String'
                    }
                }
            )

        # Publish custom CloudWatch metric
        cloudwatch.put_metric_data(
            Namespace='OrderProcessingSystem',
            MetricData=[
                {
                    'MetricName': 'OrdersCreated',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'OrderValue',
                    'Value': float(total_amount),
                    'Unit': 'None',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )

        # Return success response
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Order created successfully',
                'orderId': order_id,
                'status': 'PENDING',
                'totalAmount': float(total_amount),
                'createdAt': created_at
            }, cls=DecimalEncoder)
        }

    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'InvalidJSON',
                'message': 'Request body must be valid JSON'
            })
        }

    except Exception as e:
        print(f"Error creating order: {str(e)}")

        # Publish error metric
        cloudwatch.put_metric_data(
            Namespace='OrderProcessingSystem',
            MetricData=[
                {
                    'MetricName': 'OrderCreationErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )

        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'InternalServerError',
                'message': 'Failed to create order'
            })
        }
