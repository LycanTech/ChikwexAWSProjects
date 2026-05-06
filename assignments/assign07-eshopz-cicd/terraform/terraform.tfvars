aws_region    = "us-east-1"
dr_region     = "us-east-2"
environment   = "production"
project_name  = "chikwex-eshopz"
vpc_cidr      = "10.0.0.0/16"

# EKS
eks_cluster_version    = "1.29"
eks_node_instance_type = "t3.medium"
eks_min_nodes          = 2
eks_max_nodes          = 4
eks_desired_nodes      = 2

# RDS
db_instance_class = "db.t3.medium"
db_name           = "eshopz"
db_username       = "dbadmin"
# db_password is set via environment variable TF_VAR_db_password

# ElastiCache
elasticache_node_type = "cache.t3.micro"
