# Chikwex-EShopz Operations Runbook

## Prerequisites
- AWS CLI configured with appropriate credentials
- kubectl configured for EKS cluster
- Terraform installed (v1.14+)

## Common Operations

### 1. Deploy Infrastructure
```bash
cd terraform
export TF_VAR_db_password="YourSecurePassword123!"

# Create S3 backend bucket first
aws s3 mb s3://chikwex-eshopz-tfstate --region us-east-1
aws dynamodb create-table \
  --table-name chikwex-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Connect to EKS Cluster
```bash
aws eks update-kubeconfig --name chikwex-eshopz-eks --region us-east-1
kubectl get nodes
```

### 3. Deploy Microservices
```bash
# Apply K8s manifests
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/rbac.yaml
kubectl apply -f k8s/base/deployments.yaml
kubectl apply -f k8s/base/services.yaml
kubectl apply -f k8s/base/ingress.yaml
kubectl apply -f k8s/base/hpa.yaml
```

### 4. Deploy Monitoring Stack
```bash
kubectl apply -f k8s/monitoring/prometheus.yaml
kubectl apply -f k8s/monitoring/grafana.yaml
kubectl apply -f k8s/monitoring/elk.yaml
```

### 5. Build and Push Docker Images
```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build and push each service
for svc in user-service product-service cart-service payment-service order-service; do
  cd microservices/$svc
  docker build -t chikwex-eshopz/$svc:latest .
  docker tag chikwex-eshopz/$svc:latest ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/chikwex-eshopz/$svc:latest
  docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/chikwex-eshopz/$svc:latest
  cd ../..
done
```

### 6. Scale a Service
```bash
kubectl scale deployment user-service -n chikwex-eshopz --replicas=5
```

### 7. View Logs
```bash
# Single service
kubectl logs -f deployment/user-service -n chikwex-eshopz

# All services
kubectl logs -f -l app.kubernetes.io/part-of=chikwex-eshopz -n chikwex-eshopz
```

### 8. Rollback a Deployment
```bash
# Check rollout history
kubectl rollout history deployment/user-service -n chikwex-eshopz

# Rollback to previous version
kubectl rollout undo deployment/user-service -n chikwex-eshopz

# Rollback to specific revision
kubectl rollout undo deployment/user-service -n chikwex-eshopz --to-revision=2
```

## Troubleshooting

### Pod CrashLoopBackOff
```bash
kubectl describe pod <pod-name> -n chikwex-eshopz
kubectl logs <pod-name> -n chikwex-eshopz --previous
```

### Database Connection Issues
```bash
# Check RDS status
aws rds describe-db-clusters --db-cluster-identifier chikwex-eshopz-db --query "DBClusters[0].Status"

# Verify security group
aws rds describe-db-clusters --db-cluster-identifier chikwex-eshopz-db --query "DBClusters[0].VpcSecurityGroups"
```

### Redis Connection Issues
```bash
aws elasticache describe-replication-groups --replication-group-id chikwex-eshopz-redis --query "ReplicationGroups[0].Status"
```

## Disaster Recovery Procedures

### Full Failover
1. Promote Aurora read replica to standalone
2. Update K8s secrets with new DB endpoint
3. Restart affected deployments
4. Verify health checks pass

### Destroy Infrastructure
```bash
cd terraform
terraform destroy
```
