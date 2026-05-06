# Chikwex-EShopz Platform - Architecture Documentation

## 1. Architecture Overview

### High-Level Architecture
```
                    ┌──────────────┐
                    │  CloudFront  │
                    │    (CDN)     │
                    └──────┬───────┘
                           │
                    ┌──────┴───────┐
                    │     WAF      │
                    │  (Firewall)  │
                    └──────┬───────┘
                           │
                    ┌──────┴───────┐
                    │  API Gateway │
                    │  (Ingress)   │
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            │         EKS Cluster         │
            │                             │
            │  ┌─────┐ ┌─────┐ ┌─────┐  │
            │  │User │ │Prod │ │Cart │  │
            │  │Svc  │ │Svc  │ │Svc  │  │
            │  └──┬──┘ └──┬──┘ └──┬──┘  │
            │     │       │       │      │
            │  ┌──┴──┐ ┌──┴──┐          │
            │  │Pay  │ │Order│          │
            │  │Svc  │ │Svc  │          │
            │  └─────┘ └─────┘          │
            └──────┬──────────┬──────────┘
                   │          │
            ┌──────┴──┐  ┌───┴────┐
            │  Aurora  │  │ Redis  │
            │PostgreSQL│  │(Cache) │
            └─────────┘  └────────┘
```

### Network Architecture
```
VPC: 10.0.0.0/16
├── Public Subnets (10.0.101-103.0/24)
│   ├── ALB (Application Load Balancer)
│   ├── NAT Gateway
│   └── Internet Gateway
├── Private Subnets (10.0.1-3.0/24)
│   ├── EKS Worker Nodes
│   └── ElastiCache Redis
└── Database Subnets (10.0.201-203.0/24)
    └── Aurora PostgreSQL (Writer + Reader)
```

## 2. Microservices Architecture

| Service | Port | Responsibilities |
|---------|------|-----------------|
| user-service | 3001 | User registration, authentication, JWT tokens, profiles |
| product-service | 3002 | Product catalog, CRUD, category filtering, search |
| cart-service | 3003 | Shopping cart management, item add/remove, totals |
| payment-service | 3004 | Payment processing, refunds, transaction history |
| order-service | 3005 | Order creation, status tracking, cancellation |

### Service Communication
- **Synchronous**: REST APIs via Kubernetes service discovery
- **Asynchronous**: SQS/SNS for event-driven patterns (order events)
- **Caching**: Redis for session management and product cache

## 3. CI/CD Pipeline

```
Code Push → Build & Test → Docker Build → Security Scan → Push to ECR → Deploy to EKS → Integration Tests
                                              │                               │
                                          Trivy Scan                    Auto-Rollback
                                          (CRITICAL/HIGH)               (on failure)
```

### Pipeline Stages
1. **Build & Test**: npm install, lint, unit tests with coverage
2. **Docker Build**: Multi-stage builds, image tagging with commit SHA
3. **Security Scan**: Trivy vulnerability scanner (blocks on CRITICAL/HIGH)
4. **Push to ECR**: Only on main branch merge
5. **Deploy**: Rolling update to EKS with health checks
6. **Integration Tests**: Smoke tests against live endpoints
7. **Auto-Rollback**: `kubectl rollout undo` on any failure

### GitOps with ArgoCD
- ArgoCD watches the git repo for K8s manifest changes
- Auto-sync with self-healing enabled
- Prune orphaned resources automatically

## 4. Security Architecture

| Layer | Protection |
|-------|-----------|
| Edge | CloudFront + WAF (rate limiting, SQL injection, XSS) |
| Network | VPC isolation, private subnets, security groups |
| Cluster | K8s RBAC, service accounts, network policies |
| Application | Helmet.js, CORS, JWT authentication |
| Data | Encryption at rest (KMS), encryption in transit (TLS) |
| Secrets | AWS Secrets Manager, K8s Secrets |
| Images | ECR scanning on push, Trivy in CI pipeline |

## 5. Monitoring Stack

| Tool | Purpose | Access |
|------|---------|--------|
| Prometheus | Metrics collection (request duration, error rates) | Internal |
| Grafana | Dashboards and visualization | LoadBalancer port 80 |
| Elasticsearch | Log storage and indexing | Internal |
| Kibana | Log visualization and search | LoadBalancer port 80 |
| Fluentd | Log collection from all pods | DaemonSet |
| AWS X-Ray | Distributed tracing | AWS Console |
| CloudWatch | AWS resource monitoring, custom dashboards | AWS Console |

### Key Metrics Tracked
- Request duration per service (histogram)
- HTTP status code distribution
- Payment success/failure rates
- Order counts by status
- Pod CPU/memory utilization
- RDS connections and latency
- Redis hit/miss ratio

## 6. Disaster Recovery

| Component | Strategy | RTO | RPO |
|-----------|----------|-----|-----|
| EKS | Multi-AZ node groups | < 5 min | 0 |
| Aurora DB | Multi-AZ + read replica | < 5 min | < 1 min |
| Redis | Multi-AZ replication | < 5 min | < 1 min |
| S3/CloudFront | Cross-region replication | 0 | < 15 min |

## 7. Cost Analysis

### Monthly Estimate (Production)

| Service | Configuration | Monthly Cost |
|---------|--------------|-------------|
| EKS Cluster | Control plane | $73.00 |
| EC2 (2x t3.medium) | Worker nodes | $60.74 |
| Aurora PostgreSQL | db.t3.micro writer+reader | $58.40 |
| ElastiCache Redis | cache.t3.micro x2 | $24.82 |
| CloudFront | 100GB transfer | ~$8.50 |
| NAT Gateway | Per hour + data | ~$32.40 |
| ECR | 5 repos, ~2GB | ~$1.00 |
| S3 | Static assets | ~$1.00 |
| WAF | Web ACL + rules | ~$11.00 |
| CloudWatch | Logs + metrics | ~$10.00 |
| Secrets Manager | 1 secret | $0.40 |
| **Total** | | **~$281/month** |

### Cost Optimization
1. Use Spot instances for non-critical node groups (-60%)
2. Reserved instances for EKS nodes (-30%)
3. Aurora Serverless for variable workloads
4. S3 Intelligent-Tiering for static assets
5. Right-size instances based on actual usage metrics
