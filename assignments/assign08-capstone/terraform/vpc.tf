# =============================================================================
# VPC Infrastructure — 3 VPCs (Production, Staging, Shared Services)
# =============================================================================
# A VPC is an isolated virtual network in AWS. We create 3 to separate
# workloads by environment, which is an enterprise best practice.
#
# Why separate VPCs?
#   - Blast radius isolation: a misconfiguration in staging won't affect prod
#   - Independent security policies per environment
#   - Cleaner billing and resource tracking

# =============================================================================
# PRODUCTION VPC
# =============================================================================
resource "aws_vpc" "production" {
  cidr_block           = var.production_vpc_cidr
  enable_dns_support   = true  # Allows DNS resolution inside the VPC
  enable_dns_hostnames = true  # Assigns DNS names to EC2 instances

  tags = {
    Name = "${local.production_name}-vpc"
  }
}

# --- Production Internet Gateway ---
# An IGW allows resources in public subnets to communicate with the internet.
resource "aws_internet_gateway" "production" {
  vpc_id = aws_vpc.production.id

  tags = {
    Name = "${local.production_name}-igw"
  }
}

# --- Production Public Subnets (1 per AZ) ---
resource "aws_subnet" "production_public" {
  count                   = length(var.production_public_subnets)
  vpc_id                  = aws_vpc.production.id
  cidr_block              = var.production_public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true  # Instances here get public IPs automatically

  tags = {
    Name = "${local.production_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# --- Production Private Subnets (1 per AZ) ---
resource "aws_subnet" "production_private" {
  count             = length(var.production_private_subnets)
  vpc_id            = aws_vpc.production.id
  cidr_block        = var.production_private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.production_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

# --- Production NAT Gateway ---
# NAT Gateway sits in a public subnet and lets private subnet resources
# access the internet (e.g., for software updates) WITHOUT exposing them.
# It needs an Elastic IP (a static public IP address).
resource "aws_eip" "production_nat" {
  domain = "vpc"

  tags = {
    Name = "${local.production_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "production" {
  allocation_id = aws_eip.production_nat.id
  subnet_id     = aws_subnet.production_public[0].id  # NAT lives in public subnet

  tags = {
    Name = "${local.production_name}-nat"
  }

  depends_on = [aws_internet_gateway.production]
}

# --- Production Route Tables ---
# Public route table: sends internet traffic (0.0.0.0/0) to the IGW
resource "aws_route_table" "production_public" {
  vpc_id = aws_vpc.production.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.production.id
  }

  tags = {
    Name = "${local.production_name}-public-rt"
  }
}

# Private route table: sends internet traffic to the NAT Gateway
resource "aws_route_table" "production_private" {
  vpc_id = aws_vpc.production.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.production.id
  }

  tags = {
    Name = "${local.production_name}-private-rt"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "production_public" {
  count          = length(var.production_public_subnets)
  subnet_id      = aws_subnet.production_public[count.index].id
  route_table_id = aws_route_table.production_public.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "production_private" {
  count          = length(var.production_private_subnets)
  subnet_id      = aws_subnet.production_private[count.index].id
  route_table_id = aws_route_table.production_private.id
}

# =============================================================================
# STAGING VPC
# =============================================================================
resource "aws_vpc" "staging" {
  cidr_block           = var.staging_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.staging_name}-vpc"
  }
}

resource "aws_internet_gateway" "staging" {
  vpc_id = aws_vpc.staging.id

  tags = {
    Name = "${local.staging_name}-igw"
  }
}

resource "aws_subnet" "staging_public" {
  count                   = length(var.staging_public_subnets)
  vpc_id                  = aws_vpc.staging.id
  cidr_block              = var.staging_public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.staging_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "staging_private" {
  count             = length(var.staging_private_subnets)
  vpc_id            = aws_vpc.staging.id
  cidr_block        = var.staging_private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.staging_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

resource "aws_eip" "staging_nat" {
  domain = "vpc"

  tags = {
    Name = "${local.staging_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "staging" {
  allocation_id = aws_eip.staging_nat.id
  subnet_id     = aws_subnet.staging_public[0].id

  tags = {
    Name = "${local.staging_name}-nat"
  }

  depends_on = [aws_internet_gateway.staging]
}

resource "aws_route_table" "staging_public" {
  vpc_id = aws_vpc.staging.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.staging.id
  }

  tags = {
    Name = "${local.staging_name}-public-rt"
  }
}

resource "aws_route_table" "staging_private" {
  vpc_id = aws_vpc.staging.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.staging.id
  }

  tags = {
    Name = "${local.staging_name}-private-rt"
  }
}

resource "aws_route_table_association" "staging_public" {
  count          = length(var.staging_public_subnets)
  subnet_id      = aws_subnet.staging_public[count.index].id
  route_table_id = aws_route_table.staging_public.id
}

resource "aws_route_table_association" "staging_private" {
  count          = length(var.staging_private_subnets)
  subnet_id      = aws_subnet.staging_private[count.index].id
  route_table_id = aws_route_table.staging_private.id
}

# =============================================================================
# SHARED SERVICES VPC
# =============================================================================
# This VPC hosts centralized services (DNS, logging, monitoring, security tools)
# that all other VPCs connect to. This hub-and-spoke model is a common
# enterprise pattern — it avoids duplicating shared infrastructure.

resource "aws_vpc" "shared_services" {
  cidr_block           = var.shared_services_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.shared_services_name}-vpc"
  }
}

resource "aws_internet_gateway" "shared_services" {
  vpc_id = aws_vpc.shared_services.id

  tags = {
    Name = "${local.shared_services_name}-igw"
  }
}

resource "aws_subnet" "shared_services_public" {
  count                   = length(var.shared_services_public_subnets)
  vpc_id                  = aws_vpc.shared_services.id
  cidr_block              = var.shared_services_public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.shared_services_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "shared_services_private" {
  count             = length(var.shared_services_private_subnets)
  vpc_id            = aws_vpc.shared_services.id
  cidr_block        = var.shared_services_private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.shared_services_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  }
}

resource "aws_eip" "shared_services_nat" {
  domain = "vpc"

  tags = {
    Name = "${local.shared_services_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "shared_services" {
  allocation_id = aws_eip.shared_services_nat.id
  subnet_id     = aws_subnet.shared_services_public[0].id

  tags = {
    Name = "${local.shared_services_name}-nat"
  }

  depends_on = [aws_internet_gateway.shared_services]
}

resource "aws_route_table" "shared_services_public" {
  vpc_id = aws_vpc.shared_services.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.shared_services.id
  }

  tags = {
    Name = "${local.shared_services_name}-public-rt"
  }
}

resource "aws_route_table" "shared_services_private" {
  vpc_id = aws_vpc.shared_services.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.shared_services.id
  }

  tags = {
    Name = "${local.shared_services_name}-private-rt"
  }
}

resource "aws_route_table_association" "shared_services_public" {
  count          = length(var.shared_services_public_subnets)
  subnet_id      = aws_subnet.shared_services_public[count.index].id
  route_table_id = aws_route_table.shared_services_public.id
}

resource "aws_route_table_association" "shared_services_private" {
  count          = length(var.shared_services_private_subnets)
  subnet_id      = aws_subnet.shared_services_private[count.index].id
  route_table_id = aws_route_table.shared_services_private.id
}
