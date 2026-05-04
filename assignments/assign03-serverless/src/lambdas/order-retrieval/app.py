import json
import os
from decimal import Decimal
import boto3
from boto3.dynamodb.conditions import Key
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK for X-Ray tracing
patch_all()

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Environment variables
ORDERS_TABLE = os.environ['ORDERS_TABLE']

# Get table reference
orders_table = dynamodb.Table(ORDERS_TABLE)


class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert Decimal objects to float for JSON serialization"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)


@xray_recorder.capture('get_order_by_id')
def get_order_by_id(order_id):
    """
    Retrieves a specific order by ID

    Args:
        order_id: The order ID to retrieve

    Returns:
        dict: Order object or None if not found
    """
    try:
        response = orders_table.query(
            KeyConditionExpression=Key('orderId').eq(order_id),
            Limit=1
        )

        if response['Items']:
            return response['Items'][0]
        return None

    except Exception as e:
        print(f"Error retrieving order {order_id}: {str(e)}")
        raise


@xray_recorder.capture('list_all_orders')
def list_all_orders(status=None, limit=50):
    """
    Lists all orders, optionally filtered by status

    Args:
        status: Optional status filter (PENDING, PROCESSING, COMPLETED, FAILED)
        limit: Maximum number of orders to return

    Returns:
        list: List of order objects
    """
    try:
        if status:
            # Query using the GSI
            response = orders_table.query(
                IndexName='status-index',
                KeyConditionExpression=Key('status').eq(status),
                Limit=limit,
                ScanIndexForward=False  # Sort by createdAt descending
            )
        else:
            # Scan all orders (not recommended for production with large datasets)
            response = orders_table.scan(Limit=limit)

        return response.get('Items', [])

    except Exception as e:
        print(f"Error listing orders: {str(e)}")
        raise


def lambda_handler(event, context):
    """
    Lambda handler for order retrieval
    Handles both single order retrieval and listing all orders

    Args:
        event: API Gateway event
        context: Lambda context

    Returns:
        dict: API Gateway response with status code and body
    """
    try:
        # Check if this is a GET request for a specific order
        path_parameters = event.get('pathParameters', {})
        query_parameters = event.get('queryStringParameters', {}) or {}

        if path_parameters and 'id' in path_parameters:
            # Get specific order
            order_id = path_parameters['id']

            with xray_recorder.capture('get_single_order'):
                order = get_order_by_id(order_id)

            if not order:
                return {
                    'statusCode': 404,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'NotFound',
                        'message': f'Order {order_id} not found'
                    })
                }

            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(order, cls=DecimalEncoder)
            }

        else:
            # List all orders (with optional status filter)
            status = query_parameters.get('status')
            limit = int(query_parameters.get('limit', 50))

            # Validate status if provided
            valid_statuses = ['PENDING', 'PROCESSING', 'COMPLETED', 'FAILED']
            if status and status.upper() not in valid_statuses:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'InvalidParameter',
                        'message': f'Status must be one of: {", ".join(valid_statuses)}'
                    })
                }

            with xray_recorder.capture('list_orders'):
                orders = list_all_orders(
                    status=status.upper() if status else None,
                    limit=min(limit, 100)  # Cap at 100
                )

            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'orders': orders,
                    'count': len(orders),
                    'filter': {'status': status} if status else None
                }, cls=DecimalEncoder)
            }

    except Exception as e:
        print(f"Error in order retrieval: {str(e)}")

        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'InternalServerError',
                'message': 'Failed to retrieve orders'
            })
        }
