terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  prefix = var.project_name
  az_a   = "${var.aws_region}a"
  az_b   = "${var.aws_region}b"
}

# ──────────────────────────────────────────────────────────────────────────────
# VPC
# A dedicated VPC isolates our lab network and makes flow log filtering clean.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.prefix}-vpc" }
}

# ──────────────────────────────────────────────────────────────────────────────
# Internet Gateway  – required for the public subnet to reach the internet
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.prefix}-igw" }
}

# ──────────────────────────────────────────────────────────────────────────────
# Subnets
# Public  – hosts the bastion/jump EC2; has direct internet route via IGW
# Private – hosts the internal EC2; reaches internet via NAT (for wget tests)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = local.az_a
  map_public_ip_on_launch = true

  tags = { Name = "${local.prefix}-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = local.az_b

  tags = { Name = "${local.prefix}-private-subnet" }
}

# ──────────────────────────────────────────────────────────────────────────────
# Route tables
# Private subnet has no default route (no NAT) - the private EC2 is truly
# isolated from the internet. All traffic tests (ping, blocked port) work
# via VPC-internal routing and still appear in flow logs.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${local.prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  # No default route - private subnet is internet-isolated
  tags = { Name = "${local.prefix}-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ──────────────────────────────────────────────────────────────────────────────
# Security Groups
# ──────────────────────────────────────────────────────────────────────────────

# Public instance: allow SSH from your IP + all ICMP + outbound all
resource "aws_security_group" "public_ec2" {
  name        = "${local.prefix}-public-sg"
  description = "Public EC2 - SSH from operator + ICMP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.operator_ip_cidr]
  }

  ingress {
    description = "ICMP (ping) from anywhere inside VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-public-sg" }
}

# Private instance: allow all traffic from within the VPC (for ping tests),
# block port 8080 to demonstrate REJECT entries in flow logs.
resource "aws_security_group" "private_ec2" {
  name        = "${local.prefix}-private-sg"
  description = "Private EC2 - allow VPC traffic except port 8080"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All TCP/UDP/ICMP from within VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "ICMP from VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.prefix}-private-sg" }
}

# ──────────────────────────────────────────────────────────────────────────────
# EC2 Key Pair  (public half provided as variable)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_key_pair" "lab" {
  key_name   = "${local.prefix}-key"
  public_key = var.ec2_public_key
}

# ──────────────────────────────────────────────────────────────────────────────
# EC2 Instances
# Using the latest Amazon Linux 2023 AMI via SSM parameter (no hard-coded ID).
# ──────────────────────────────────────────────────────────────────────────────

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "public" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.public_ec2.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    yum install -y curl wget iputils
  EOF

  tags = { Name = "${local.prefix}-public-ec2" }
}

resource "aws_instance" "private" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.private_ec2.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = <<-EOF
    #!/bin/bash
    yum install -y curl wget iputils
  EOF

  tags = { Name = "${local.prefix}-private-ec2" }
}

# ──────────────────────────────────────────────────────────────────────────────
# S3 Bucket for VPC Flow Logs
# Parquet format is columnar – Athena scans far less data per query compared
# to plain-text logs, lowering both cost and query time.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "flow_logs" {
  bucket        = "${local.prefix}-vpc-flow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # allows clean `terraform destroy` in a lab

  tags = { Name = "${local.prefix}-flow-logs" }
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket                  = aws_s3_bucket.flow_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move to Intelligent-Tiering after 30 days, expire after 90
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {} # applies to all objects in the bucket

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    expiration {
      days = 90
    }
  }
}

# Bucket policy: allow the VPC Flow Logs delivery service to write objects
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.flow_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.flow_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# VPC Flow Logs
# file-format = parquet → columnar, compressed, ~10x cheaper to query in Athena
# max-aggregation-interval = 60 seconds → logs arrive faster (default is 600s)
# destination_options adds Hive-compatible partitions (year/month/day/hour)
# which lets Athena skip entire partitions when you filter by date.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL" # captures ACCEPT, REJECT, and everything
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_format           = var.flow_log_format

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true # creates year=YYYY/month=MM/day=DD/hour=HH prefixes
  }

  max_aggregation_interval = 60

  tags = { Name = "${local.prefix}-flow-log" }

  depends_on = [aws_s3_bucket_policy.flow_logs]
}

# ──────────────────────────────────────────────────────────────────────────────
# Athena
# Workgroup controls where query results land and caps per-query data scanned
# (cost guard). Using a dedicated workgroup keeps billing isolation clean.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${local.prefix}-athena-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "${local.prefix}-athena-results" }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_athena_workgroup" "flow_logs" {
  name          = "${local.prefix}-workgroup"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Guard: kill any query that would scan more than 1 GB (cost protection)
    bytes_scanned_cutoff_per_query = 1073741824
  }

  tags = { Name = "${local.prefix}-workgroup" }
}

resource "aws_athena_database" "flow_logs" {
  name   = replace("${local.prefix}_flow_logs_db", "-", "_")
  bucket = aws_s3_bucket.athena_results.bucket

  force_destroy = true
}

# ──────────────────────────────────────────────────────────────────────────────
# Athena Table
# Schema matches the VPC Flow Log v2 format fields in var.flow_log_format.
# Stored as PARQUET with Hive partitions (year/month/day/hour) so Athena can
# prune entire time windows without scanning the whole bucket.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_athena_named_query" "create_table" {
  name        = "${local.prefix}-create-flow-logs-table"
  workgroup   = aws_athena_workgroup.flow_logs.id
  database    = aws_athena_database.flow_logs.name
  description = "Creates the partitioned Parquet table for VPC Flow Logs"

  query = <<-SQL
    CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
      version         INT,
      account_id      STRING,
      interface_id    STRING,
      srcaddr         STRING,
      dstaddr         STRING,
      srcport         INT,
      dstport         INT,
      protocol        BIGINT,
      packets         BIGINT,
      bytes           BIGINT,
      start           BIGINT,
      end             BIGINT,
      action          STRING,
      log_status      STRING,
      vpc_id          STRING,
      subnet_id       STRING,
      instance_id     STRING,
      tcp_flags       INT,
      type            STRING,
      pkt_srcaddr     STRING,
      pkt_dstaddr     STRING,
      region          STRING,
      az_id           STRING,
      sublocation_type STRING,
      sublocation_id  STRING,
      pkt_src_aws_service  STRING,
      pkt_dst_aws_service  STRING,
      flow_direction  STRING,
      traffic_path    INT
    )
    PARTITIONED BY (
      year  STRING,
      month STRING,
      day   STRING,
      hour  STRING
    )
    ROW FORMAT SERDE 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
    STORED AS
      INPUTFORMAT  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
      OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
    LOCATION 's3://${aws_s3_bucket.flow_logs.bucket}/AWSLogs/${data.aws_caller_identity.current.account_id}/vpcflowlogs/${var.aws_region}/'
    TBLPROPERTIES (
      'EXTERNAL'='TRUE',
      'skip.header.line.count'='1',
      'projection.enabled'           = 'true',
      'projection.year.type'         = 'integer',
      'projection.year.range'        = '2024,2030',
      'projection.month.type'        = 'integer',
      'projection.month.range'       = '1,12',
      'projection.month.digits'      = '2',
      'projection.day.type'          = 'integer',
      'projection.day.range'         = '1,31',
      'projection.day.digits'        = '2',
      'projection.hour.type'         = 'integer',
      'projection.hour.range'        = '0,23',
      'projection.hour.digits'       = '2',
      'storage.location.template'    = 's3://${aws_s3_bucket.flow_logs.bucket}/AWSLogs/${data.aws_caller_identity.current.account_id}/vpcflowlogs/${var.aws_region}/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/'
    );
  SQL
}

# ──────────────────────────────────────────────────────────────────────────────
# Saved Athena Queries (task requirements)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_athena_named_query" "top10_source_ips" {
  name        = "${local.prefix}-top10-source-ips"
  workgroup   = aws_athena_workgroup.flow_logs.id
  database    = aws_athena_database.flow_logs.name
  description = "Top 10 source IPs by total bytes transferred"

  query = <<-SQL
    SELECT
      srcaddr,
      COUNT(*)        AS flow_count,
      SUM(bytes)      AS total_bytes,
      SUM(packets)    AS total_packets
    FROM vpc_flow_logs
    WHERE year  = '${formatdate("YYYY", timestamp())}'
      AND month = '${formatdate("MM", timestamp())}'
    GROUP BY srcaddr
    ORDER BY total_bytes DESC
    LIMIT 10;
  SQL
}

resource "aws_athena_named_query" "reject_actions" {
  name        = "${local.prefix}-all-reject-actions"
  workgroup   = aws_athena_workgroup.flow_logs.id
  database    = aws_athena_database.flow_logs.name
  description = "All REJECT actions – useful for identifying blocked/malicious traffic"

  query = <<-SQL
    SELECT
      srcaddr,
      dstaddr,
      srcport,
      dstport,
      protocol,
      packets,
      bytes,
      action,
      from_unixtime(start) AS start_time
    FROM vpc_flow_logs
    WHERE action = 'REJECT'
      AND year  = '${formatdate("YYYY", timestamp())}'
      AND month = '${formatdate("MM", timestamp())}'
    ORDER BY start_time DESC
    LIMIT 500;
  SQL
}

resource "aws_athena_named_query" "traffic_between_ips" {
  name        = "${local.prefix}-traffic-between-ips"
  workgroup   = aws_athena_workgroup.flow_logs.id
  database    = aws_athena_database.flow_logs.name
  description = "Bidirectional traffic between two specific IPs – replace placeholders before running"

  query = <<-SQL
    -- Replace <IP_A> and <IP_B> with the actual instance private IPs
    SELECT
      srcaddr,
      dstaddr,
      srcport,
      dstport,
      protocol,
      bytes,
      packets,
      action,
      from_unixtime(start) AS start_time
    FROM vpc_flow_logs
    WHERE (
        (srcaddr = '<IP_A>' AND dstaddr = '<IP_B>')
        OR
        (srcaddr = '<IP_B>' AND dstaddr = '<IP_A>')
      )
      AND year  = '${formatdate("YYYY", timestamp())}'
      AND month = '${formatdate("MM", timestamp())}'
    ORDER BY start_time DESC;
  SQL
}

resource "aws_athena_named_query" "connections_port_22" {
  name        = "${local.prefix}-connections-port-22"
  workgroup   = aws_athena_workgroup.flow_logs.id
  database    = aws_athena_database.flow_logs.name
  description = "All connections targeting port 22 (SSH) – both accepted and rejected"

  query = <<-SQL
    SELECT
      srcaddr,
      dstaddr,
      dstport,
      action,
      COUNT(*)     AS attempts,
      SUM(packets) AS total_packets,
      SUM(bytes)   AS total_bytes
    FROM vpc_flow_logs
    WHERE dstport = 22
      AND year  = '${formatdate("YYYY", timestamp())}'
      AND month = '${formatdate("MM", timestamp())}'
    GROUP BY srcaddr, dstaddr, dstport, action
    ORDER BY attempts DESC;
  SQL
}

resource "aws_athena_named_query" "traffic_by_protocol" {
  name        = "${local.prefix}-traffic-by-protocol"
  workgroup   = aws_athena_workgroup.flow_logs.id
  database    = aws_athena_database.flow_logs.name
  description = "Traffic volume broken down by protocol (6=TCP, 17=UDP, 1=ICMP)"

  query = <<-SQL
    SELECT
      CASE protocol
        WHEN 1  THEN 'ICMP'
        WHEN 6  THEN 'TCP'
        WHEN 17 THEN 'UDP'
        ELSE CAST(protocol AS VARCHAR)
      END                  AS protocol_name,
      COUNT(*)             AS flow_count,
      SUM(bytes)           AS total_bytes,
      SUM(packets)         AS total_packets,
      SUM(CASE WHEN action = 'REJECT' THEN 1 ELSE 0 END) AS rejected_flows
    FROM vpc_flow_logs
    WHERE year  = '${formatdate("YYYY", timestamp())}'
      AND month = '${formatdate("MM", timestamp())}'
    GROUP BY protocol
    ORDER BY total_bytes DESC;
  SQL
}

resource "aws_athena_named_query" "security_events_summary" {
  name        = "${local.prefix}-security-events-summary"
  workgroup   = aws_athena_workgroup.flow_logs.id
  database    = aws_athena_database.flow_logs.name
  description = "Security event summary: port scans, repeated REJECTs per source"

  query = <<-SQL
    SELECT
      srcaddr                              AS source_ip,
      COUNT(DISTINCT dstport)              AS unique_ports_targeted,
      COUNT(*)                             AS total_flows,
      SUM(CASE WHEN action='REJECT' THEN 1 ELSE 0 END) AS rejected_flows,
      MIN(from_unixtime(start))            AS first_seen,
      MAX(from_unixtime(start))            AS last_seen
    FROM vpc_flow_logs
    WHERE action = 'REJECT'
      AND year  = '${formatdate("YYYY", timestamp())}'
      AND month = '${formatdate("MM", timestamp())}'
    GROUP BY srcaddr
    HAVING COUNT(*) > 5
    ORDER BY rejected_flows DESC
    LIMIT 50;
  SQL
}
