# Neha's AWS & DevOps Assignments

A collection of hands-on AWS and DevOps assignments covering cloud infrastructure, automation, containerization, CI/CD pipelines, and observability. Each assignment is self-contained with its own documentation, infrastructure-as-code templates, and deployment guides.

---

## Assignments

| # | Folder | Topic | Key Technologies |
| --- | ------ | ----- | ---------------- |
| 3 | [assign03-serverless](assignments/assign03-serverless/) | Serverless Order Processing System | Lambda, API Gateway, DynamoDB, SQS, SNS, Step Functions, X-Ray |
| 4 | [assign04-dr](assignments/assign04-dr/) | Disaster Recovery & High Availability | Multi-AZ, RTO/RPO planning, failover strategies |
| 5 | [assign05-ansible](assignments/assign05-ansible/) | Infrastructure Automation with Ansible | Ansible, EC2, Dynamic Inventory, Nginx, PostgreSQL, Molecule |
| 6 | [assign06-docker-compose](assignments/assign06-docker-compose/) | Multi-Tier Containerized Application | Docker Compose, Nginx, React, Flask, PostgreSQL, Redis |
| 7 | [assign07-cicd](assignments/assign07-cicd/) | CI/CD Pipeline | GitHub Actions, Helm, Kubernetes |
| 8 | [assign08-capstone](assignments/assign08-capstone/) | Secure Multi-VPC Enterprise Network | Terraform, Transit Gateway, Site-to-Site VPN, Network Firewall |
| 10 | [assign10-autoscaling](assignments/assign10-autoscaling/) | Auto Scaling with Lifecycle Hooks | EC2 Auto Scaling, Lambda, SSM, EventBridge, Terraform |
| 11 | [assign11-rds-rotation](assignments/assign11-rds-rotation/) | RDS Secret Rotation | Lambda, Secrets Manager, RDS |
| 12 | [assign12-cloudwatch](assignments/assign12-cloudwatch/) | CloudWatch Logs & Alerting | CloudWatch Logs Insights, Metric Filters, Alarms, SNS |
| 13 | [assign13-dynamodb-streams](assignments/assign13-dynamodb-streams/) | DynamoDB Streams with Lambda | DynamoDB Streams, Lambda, event-driven aggregation |
| 14 | [assign14-eventbridge](assignments/assign14-eventbridge/) | EventBridge Automated Scheduler | EventBridge, Lambda, event routing |
| 15 | [assign15-vpc-flow-logs](assignments/assign15-vpc-flow-logs/) | VPC Flow Logs Analysis | VPC Flow Logs, Athena, S3, network traffic analysis |
| S3 | [s3-replication-failover](assignments/s3-replication-failover/) | Multi-Region S3 Replication & Failover | S3 CRR, versioning, delete marker replication |

---

## Assignment Summaries

### Assignment 3 — Serverless Order Processing

A fully serverless order management system using AWS managed services. Orders flow through API Gateway → Lambda → DynamoDB with Step Functions orchestrating the processing pipeline, SQS for decoupling, and SNS for notifications. Includes distributed tracing with X-Ray.

### Assignment 4 — Disaster Recovery & High Availability

Architecture and runbook for a highly available, disaster-resilient system. Covers multi-AZ deployments, RDS failover, Route 53 health checks, and RTO/RPO planning with a documented HA/DR plan.

### Assignment 5 — Infrastructure Automation with Ansible

Production-grade Ansible automation for deploying and managing web and database servers on AWS. Features dynamic EC2 inventory discovery, modular roles (Nginx, PostgreSQL, security hardening), AWS service integration (SSM, CloudWatch, Secrets Manager), and a GitHub Actions CI/CD pipeline with Molecule testing.

### Assignment 6 — Multi-Tier Docker Compose Application

A complete containerized application stack with Nginx as a reverse proxy in front of a React frontend and Flask backend, backed by PostgreSQL and Redis. Includes multi-stage Docker builds, health checks, custom networks, named volumes, and separate dev/prod compose configurations.

### Assignment 7 — CI/CD Pipeline

End-to-end CI/CD pipeline using GitHub Actions to build, test, and deploy a Helm-packaged application to Kubernetes. Includes a deployment runbook and rollback procedures.

### Assignment 8 — Secure Multi-VPC Enterprise Network (Capstone)

Enterprise-grade network architecture with defense-in-depth security. Implements a hub-and-spoke VPC topology via AWS Transit Gateway, Site-to-Site VPN for on-premises connectivity, AWS Network Firewall for deep packet inspection, and VPC Flow Logs for traffic auditing. Fully defined in Terraform.

### Assignment 10 — Auto Scaling with Lifecycle Hooks

EC2 Auto Scaling Group where instances are configured automatically on launch via Lambda + SSM — no user data scripts. EventBridge triggers the Lambda on lifecycle hook events, and Terraform manages the full infrastructure.

### Assignment 11 — RDS Secret Rotation

Automated database credential rotation using AWS Secrets Manager and a custom Lambda rotation function. Keeps RDS passwords rotated on a schedule without application downtime.

### Assignment 12 — CloudWatch Logs & Alerting

Advanced log analysis pipeline using CloudWatch Logs Insights queries and metric filters to extract custom metrics from application logs. Includes CloudWatch Alarms with SNS notifications and reusable Insights query templates.

### Assignment 13 — DynamoDB Streams with Lambda

Event-driven aggregation pattern using DynamoDB Streams. A Lambda function processes stream records in real time to maintain aggregated counters and summaries without polling.

### Assignment 14 — EventBridge Automated Scheduler

Automated task scheduling with Amazon EventBridge. Demonstrates event routing rules, scheduled expressions, and Lambda targets for recurring infrastructure automation tasks.

### Assignment 15 — VPC Flow Logs Analysis with Athena

Network traffic analysis pipeline that stores VPC Flow Logs in S3 and queries them using Amazon Athena. Includes partitioned table schemas and sample queries for identifying top talkers, rejected connections, and anomalous traffic patterns.

### S3 Replication & Failover

Cross-region S3 replication setup with automated failover. Covers Cross-Region Replication (CRR) configuration, delete marker replication, versioning, and tested RTO/RPO with observed replication lag results.

---

## Common Patterns

- **Infrastructure-as-Code** — Terraform and AWS SAM used throughout for repeatable deployments
- **Security** — IAM least-privilege, encryption at rest/in transit, VPC isolation, secrets management
- **Observability** — CloudWatch metrics/logs/alarms, X-Ray tracing, VPC Flow Logs
- **Naming convention** — `chikwex-` prefix on AWS resources for easy identification and filtering
- **Cleanup** — Every assignment includes teardown instructions to avoid ongoing costs

---

## Prerequisites

Most assignments require:

- AWS Account with appropriate IAM permissions
- AWS CLI v2 configured (`aws configure`)
- Terraform >= 1.0 (for IaC assignments)
- Docker & Docker Compose (for containerization assignments)
- Python 3.9+ and Ansible 2.14+ (for Assignment 5)

Refer to each assignment's README for specific prerequisites.

---

## Repository Structure

```
assignments/
├── assign03-serverless/       # Serverless order processing
├── assign04-dr/               # Disaster recovery & HA
├── assign05-ansible/          # Ansible infrastructure automation
├── assign06-docker-compose/   # Multi-tier Docker application
├── assign07-cicd/             # CI/CD pipeline
├── assign08-capstone/         # Secure multi-VPC network
├── assign10-autoscaling/      # Auto scaling with lifecycle hooks
├── assign11-rds-rotation/     # RDS secret rotation
├── assign12-cloudwatch/       # CloudWatch logs & alerting
├── assign13-dynamodb-streams/ # DynamoDB streams aggregation
├── assign14-eventbridge/      # EventBridge scheduler
├── assign15-vpc-flow-logs/    # VPC flow logs analysis
└── s3-replication-failover/   # Multi-region S3 replication
```
