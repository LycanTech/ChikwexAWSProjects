# Assignment 7 — Chikwex-EShopz: End-to-End DevOps Pipeline

## Overview

A production-ready e-commerce platform with complete DevOps automation. Five Node.js microservices run on EKS, deployed via a GitHub Actions CI/CD pipeline with Trivy security scanning, GitOps via ArgoCD, and a full observability stack (Prometheus, Grafana, ELK).

---

## Architecture

```
                    ┌──────────────┐
                    │  CloudFront  │
                    │    (CDN)     │
                    └──────┬───────┘
                           │
                    ┌──────┴───────┐
                    │     WAF      │
                    └──────┬───────┘
                           │
                    ┌──────┴───────┐
                    │  API Gateway │
                    │  (Ingress)   │
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            │         EKS Cluster         │
            │  (chikwex-eshopz-eks)       │
            │                             │
            │  user  product  cart        │
            │  :3001  :3002  :3003        │
            │                             │
            │  payment    order           │
            │   :3004     :3005           │
            └──────┬──────────┬──────────┘
                   │          │
            ┌──────┴──┐  ┌───┴────┐
            │  Aurora  │  │ Redis  │
            │PostgreSQL│  │(Cache) │
            └─────────┘  └────────┘
```

### Network Layout

```
VPC 10.0.0.0/16
├── Public Subnets (10.0.101-103.0/24)   ← ALB, NAT Gateway, IGW
├── Private Subnets (10.0.1-3.0/24)      ← EKS worker nodes, Redis
└── Database Subnets (10.0.201-203.0/24) ← Aurora PostgreSQL
```

---

## Microservices

| Service | Port | Responsibilities |
| --- | --- | --- |
| `user-service` | 3001 | Registration, authentication, JWT, profiles |
| `product-service` | 3002 | Product catalog, CRUD, categories, search |
| `cart-service` | 3003 | Shopping cart management, totals |
| `payment-service` | 3004 | Payment processing, refunds, transaction history |
| `order-service` | 3005 | Order creation, status tracking, cancellation |

**Synchronous communication**: REST via Kubernetes service discovery
**Asynchronous**: SQS/SNS for order events
**Caching**: Redis for session management and product cache

---

## CI/CD Pipeline

```
Code Push → Build & Test → Docker Build → Trivy Scan → Push to ECR → Deploy to EKS → Integration Tests
                                               │                           │
                                     Blocks on CRITICAL/HIGH         Auto-Rollback
```

### Pipeline stages (`.github/workflows/ci-cd.yaml`)

1. **Build & Test** — `npm ci`, lint, unit tests with coverage (matrix across all 5 services + frontend)
2. **Docker Build** — multi-stage builds, tagged with commit SHA
3. **Trivy Security Scan** — blocks pipeline on CRITICAL or HIGH CVEs
4. **Push to ECR** — only on merge to `main`
5. **Deploy to EKS** — rolling update via `kubectl` with health checks
6. **Integration Tests** — smoke tests against live endpoints
7. **Auto-Rollback** — `kubectl rollout undo` on any failure

### GitOps with ArgoCD

ArgoCD watches the repo for K8s manifest changes, auto-syncs with self-healing, and prunes orphaned resources automatically. ArgoCD app config is at [k8s/base/argocd-app.yaml](k8s/base/argocd-app.yaml).

### Azure Pipelines

An alternative pipeline is defined in [azure-pipelines.yaml](azure-pipelines.yaml) for Azure DevOps environments.

---

## Project Structure

```
├── .github/workflows/ci-cd.yaml      # GitHub Actions pipeline
├── azure-pipelines.yaml              # Azure DevOps pipeline
├── microservices/
│   ├── user-service/                 # Node.js + Express
│   ├── product-service/
│   ├── cart-service/
│   ├── payment-service/
│   └── order-service/
├── frontend/                         # Next.js app
├── helm/chikwex-eshopz/             # Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-prod.yaml
│   └── templates/                    # deployment, service, ingress, hpa, secrets
├── k8s/
│   ├── base/                         # namespace, RBAC, deployments, services, HPA
│   └── monitoring/                   # Prometheus, Grafana, ELK, node-exporter
├── terraform/
│   ├── eks.tf                        # EKS cluster
│   ├── vpc.tf                        # VPC, subnets, NAT
│   ├── rds.tf                        # Aurora PostgreSQL
│   ├── elasticache.tf               # Redis
│   ├── cloudfront.tf                # CDN
│   ├── security.tf                  # WAF, security groups
│   └── modules/eks/                 # EKS module
├── ansible/                          # EC2 config management
│   ├── playbook.yaml
│   └── templates/                   # CloudWatch agent, logrotate
└── docs/
    ├── architecture.md              # Full architecture docs
    └── runbook.md                   # Operational runbook
```

---

## Security

| Layer | Protection |
| --- | --- |
| Edge | CloudFront + WAF (rate limiting, SQL injection, XSS rules) |
| Network | VPC isolation, private subnets, security groups |
| Cluster | K8s RBAC, service accounts, network policies |
| Application | Helmet.js, CORS, JWT authentication |
| Data | KMS encryption at rest, TLS in transit |
| Secrets | AWS Secrets Manager + K8s Secrets |
| Images | ECR scanning on push, Trivy in CI pipeline |

---

## Observability

| Tool | Purpose |
| --- | --- |
| Prometheus | Metrics collection (request duration, error rates, pod utilization) |
| Grafana | Dashboards and visualization |
| Elasticsearch + Kibana | Log storage, indexing, and search |
| Fluentd | Log collection DaemonSet from all pods |
| AWS X-Ray | Distributed tracing across microservices |
| CloudWatch | AWS resource monitoring, custom dashboards |

---

## Infrastructure Deployment

### Prerequisites

- Terraform >= 1.0
- `kubectl` + `helm` configured
- AWS CLI with EKS access
- Docker (for local builds)

### Deploy infrastructure

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### Configure kubectl for EKS

```bash
aws eks update-kubeconfig \
  --name chikwex-eshopz-eks \
  --region us-east-1
```

### Deploy via Helm

```bash
helm upgrade --install chikwex-eshopz ./helm/chikwex-eshopz \
  --namespace chikwex-eshopz \
  --create-namespace \
  -f helm/chikwex-eshopz/values-prod.yaml
```

### Required GitHub Secrets

| Secret | Purpose |
| --- | --- |
| `AWS_ACCOUNT_ID` | ECR registry URL construction |
| `AWS_ACCESS_KEY_ID` | AWS authentication |
| `AWS_SECRET_ACCESS_KEY` | AWS authentication |

---

## Disaster Recovery

| Component | Strategy | RTO | RPO |
| --- | --- | --- | --- |
| EKS | Multi-AZ node groups | < 5 min | 0 |
| Aurora DB | Multi-AZ + read replica | < 5 min | < 1 min |
| Redis | Multi-AZ replication | < 5 min | < 1 min |
| S3/CloudFront | Cross-region replication | ~0 | < 15 min |

---

## Cost Estimate (Production)

| Service | Monthly Cost |
| --- | --- |
| EKS control plane | $73.00 |
| EC2 worker nodes (2× t3.medium) | $60.74 |
| Aurora PostgreSQL (writer + reader) | $58.40 |
| ElastiCache Redis (2× cache.t3.micro) | $24.82 |
| NAT Gateway | $32.40 |
| WAF | $11.00 |
| CloudWatch | $10.00 |
| CloudFront (100GB transfer) | $8.50 |
| Other (ECR, S3, Secrets Manager) | $2.40 |
| **Total** | **~$281/month** |

**Cost optimization**: Spot instances for non-critical node groups (−60%), Reserved Instances for workers (−30%), Aurora Serverless for variable workloads.

---

## Documentation

- [Architecture](docs/architecture.md) — network diagram, service communication, security layers
- [Runbook](docs/runbook.md) — common operations, rollback, scaling procedures
