# ==============================================================
# ELASTICACHE - Redis for session management
# ==============================================================

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-cache-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-cache-subnet"
  }
}

resource "aws_security_group" "elasticache" {
  name_prefix = "${var.project_name}-cache-"
  vpc_id      = data.aws_vpc.existing.id
  description = "ElastiCache security group"

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    description     = "Redis from EKS nodes"
  }

  tags = {
    Name = "${var.project_name}-cache-sg"
  }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-redis"
  description          = "Redis cluster for session management"

  node_type            = var.elasticache_node_type
  num_cache_clusters   = 2
  port                 = 6379
  engine               = "redis"
  engine_version       = "7.0"
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = true

  tags = {
    Name = "${var.project_name}-redis"
  }
}
