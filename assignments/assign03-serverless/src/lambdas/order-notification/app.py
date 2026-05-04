import json
import os
from datetime import datetime
import boto3
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK for X-Ray tracing
patch_all()

# Initialize AWS clients
ses = boto3.client('ses')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
ORDER_TOPIC_ARN = os.environ.get('ORDER_TOPIC_ARN', '')


@xray_recorder.capture('send_email_notification')
def send_email_notification(order_id, status, customer_email, message):
    """
    Sends email notification using Amazon SES
    Note: In production, you need to verify email addresses or domain in SES

    Args:
        order_id: The order ID
        status: Order status
        customer_email: Customer email address
        message: Notification message

    Returns:
        dict: Email send result
    """
    try:
        # In production environment, uncomment this section
        # Requires SES to be configured and email addresses verified
        """
        response = ses.send_email(
            Source='noreply@yourcompany.com',
            Destination={
                'ToAddresses': [customer_email]
            },
            Message={
                'Subject': {
                    'Data': f'Order {order_id} - {status}',
                    'Charset': 'UTF-8'
                },
                'Body': {
                    'Text': {
                        'Data': message,
                        'Charset': 'UTF-8'
                    },
                    'Html': {
                        'Data': f'''
                        <html>
                        <body>
                            <h2>Order Update</h2>
                            <p><strong>Order ID:</strong> {order_id}</p>
                            <p><strong>Status:</strong> {status}</p>
                            <p>{message}</p>
                            <hr>
                            <p><small>Thank you for your order!</small></p>
                        </body>
                        </html>
                        ''',
                        'Charset': 'UTF-8'
                    }
                }
            }
        )
        return {'status': 'sent', 'messageId': response['MessageId']}
        """

        # For demo purposes, just log the email
        print(f"EMAIL NOTIFICATION: To={customer_email}, OrderId={order_id}, Status={status}")
        print(f"Message: {message}")

        return {'status': 'logged', 'messageId': 'demo-message-id'}

    except Exception as e:
        print(f"Error sending email: {str(e)}")
        return {'status': 'failed', 'error': str(e)}


@xray_recorder.capture('send_sms_notification')
def send_sms_notification(order_id, status, phone_number, message):
    """
    Sends SMS notification using Amazon SNS
    Note: Requires phone number verification in SNS sandbox mode

    Args:
        order_id: The order ID
        status: Order status
        phone_number: Customer phone number
        message: Notification message

    Returns:
        dict: SMS send result
    """
    try:
        # In production environment, uncomment this section
        """
        response = sns.publish(
            PhoneNumber=phone_number,
            Message=f"Order {order_id} - {status}: {message}",
            MessageAttributes={
                'AWS.SNS.SMS.SenderID': {
                    'DataType': 'String',
                    'StringValue': 'YourCompany'
                },
                'AWS.SNS.SMS.SMSType': {
                    'DataType': 'String',
                    'StringValue': 'Transactional'
                }
            }
        )
        return {'status': 'sent', 'messageId': response['MessageId']}
        """

        # For demo purposes, just log the SMS
        print(f"SMS NOTIFICATION: To={phone_number}, OrderId={order_id}, Status={status}")
        print(f"Message: {message}")

        return {'status': 'logged', 'messageId': 'demo-sms-id'}

    except Exception as e:
        print(f"Error sending SMS: {str(e)}")
        return {'status': 'failed', 'error': str(e)}


def lambda_handler(event, context):
    """
    Lambda handler for order notifications
    Processes SNS messages and sends notifications via email/SMS

    Args:
        event: SNS event
        context: Lambda context

    Returns:
        dict: Notification result
    """
    try:
        print(f"Received event: {json.dumps(event)}")

        # Process SNS records
        for record in event.get('Records', []):
            if record['EventSource'] == 'aws:sns':
                # Parse SNS message
                sns_message = json.loads(record['Sns']['Message'])

                order_id = sns_message.get('orderId', 'unknown')
                status = sns_message.get('status', 'UNKNOWN')
                message = sns_message.get('message', 'Your order has been updated')

                print(f"Processing notification for order: {order_id}, status: {status}")

                # Get customer contact information from the message or database
                customer_email = sns_message.get('customerEmail', 'customer@example.com')
                customer_phone = sns_message.get('customerPhone', '+1234567890')

                # Send email notification
                with xray_recorder.capture('send_email'):
                    email_result = send_email_notification(
                        order_id=order_id,
                        status=status,
                        customer_email=customer_email,
                        message=message
                    )

                # Send SMS notification (optional)
                with xray_recorder.capture('send_sms'):
                    sms_result = send_sms_notification(
                        order_id=order_id,
                        status=status,
                        phone_number=customer_phone,
                        message=message
                    )

                # Publish custom metrics
                cloudwatch.put_metric_data(
                    Namespace='OrderProcessingSystem',
                    MetricData=[
                        {
                            'MetricName': 'NotificationsSent',
                            'Value': 1,
                            'Unit': 'Count',
                            'Dimensions': [
                                {
                                    'Name': 'NotificationType',
                                    'Value': 'Email'
                                },
                                {
                                    'Name': 'Status',
                                    'Value': email_result['status']
                                }
                            ]
                        },
                        {
                            'MetricName': 'NotificationsSent',
                            'Value': 1,
                            'Unit': 'Count',
                            'Dimensions': [
                                {
                                    'Name': 'NotificationType',
                                    'Value': 'SMS'
                                },
                                {
                                    'Name': 'Status',
                                    'Value': sms_result['status']
                                }
                            ]
                        }
                    ]
                )

                print(f"Notifications sent - Email: {email_result['status']}, SMS: {sms_result['status']}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notifications processed successfully'
            })
        }

    except Exception as e:
        print(f"Error processing notification: {str(e)}")

        # Publish error metric
        cloudwatch.put_metric_data(
            Namespace='OrderProcessingSystem',
            MetricData=[
                {
                    'MetricName': 'NotificationErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )

        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'InternalServerError',
                'message': str(e)
            })
        }
