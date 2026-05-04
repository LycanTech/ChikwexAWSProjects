# ==============================================================
# VPC - Using existing VPC with new subnets for EKS, RDS, ElastiCache
# ==============================================================

# Use existing VPC (due to VPC limit)
data "aws_vpc" "existing" {
  id = "vpc-004d871072ca79b9c"
}

# Use existing Internet Gateway attached to this VPC
data "aws_internet_gateway" "existing" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.existing.id]
  }
}

# NAT Gateway (for private subnets)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [data.aws_internet_gateway.existing]
}

# ==============================================================
# SUBNETS - Using non-overlapping CIDRs within 10.0.0.0/16
# ==============================================================

# Public Subnets (for ALB, NAT Gateway) - 10.0.50-52.0/24
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = data.aws_vpc.existing.id
  cidr_block              = "10.0.${50 + count.index}.0/24"
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                              = "${var.project_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                          = "1"
    "kubernetes.io/cluster/${var.project_name}-eks"   = "owned"
  }
}

# Private Subnets (for EKS worker nodes) - 10.0.60-62.0/24
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = "10.0.${60 + count.index}.0/24"
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                              = "${var.project_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"                 = "1"
    "kubernetes.io/cluster/${var.project_name}-eks"   = "owned"
  }
}

# Database Subnets - 10.0.70-72.0/24
resource "aws_subnet" "database" {
  count             = 3
  vpc_id            = data.aws_vpc.existing.id
  cidr_block        = "10.0.${70 + count.index}.0/24"
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-db-${var.availability_zones[count.index]}"
  }
}

# ==============================================================
# ROUTE TABLES
# ==============================================================

# Public route table
resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.existing.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.existing.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.existing.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Database route table (no internet access)
resource "aws_route_table" "database" {
  vpc_id = data.aws_vpc.existing.id

  tags = {
    Name = "${var.project_name}-db-rt"
  }
}

resource "aws_route_table_association" "database" {
  count          = 3
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}
