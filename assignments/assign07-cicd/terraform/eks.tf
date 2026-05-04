# ==============================================================
# EKS CLUSTER - Kubernetes for microservices
# ==============================================================

module "eks" {
  source = "./modules/eks"

  cluster_name       = "${var.project_name}-eks"
  cluster_version    = var.eks_cluster_version
  vpc_id             = data.aws_vpc.existing.id
  private_subnet_ids = aws_subnet.private[*].id
  public_subnet_ids  = aws_subnet.public[*].id

  node_instance_type = var.eks_node_instance_type
  min_nodes          = var.eks_min_nodes
  max_nodes          = var.eks_max_nodes
  desired_nodes      = var.eks_desired_nodes

  project_name = var.project_name
  environment  = var.environment
}
