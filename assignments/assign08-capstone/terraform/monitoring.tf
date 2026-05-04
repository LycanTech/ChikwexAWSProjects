# =============================================================================
# Monitoring — Athena, CloudWatch Insights, Alerts
# =============================================================================

# =============================================================================
# ATHENA — Query Flow Logs in S3 with SQL
# =============================================================================
# Athena lets you run SQL queries against flow log files stored in S3.
# No servers to manage — just point it at your data and query.

# Athena database for flow log analysis
resource "aws_athena_database" "flow_logs" {
  name   = "${replace(local.prefix, "-", "_")}_flow_logs"
  bucket = aws_s3_bucket.athena_results.id
}

# S3 bucket to store Athena query results
resource "aws_s3_bucket" "athena_results" {
  bucket_prefix = "${local.prefix}-athena-results-"
  force_destroy = true

  tags = {
    Name = "${local.prefix}-athena-results"
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Athena named query — Create the flow logs table
resource "aws_athena_named_query" "create_flow_logs_table" {
  name        = "${local.prefix}-create-flow-logs-table"
  database    = aws_athena_database.flow_logs.name
  description = "Creates the VPC Flow Logs table for querying"

  query = <<-EOT
    CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
      version int,
      account_id string,
      interface_id string,
      srcaddr string,
      dstaddr string,
      srcport int,
      dstport int,
      protocol bigint,
      packets bigint,
      bytes bigint,
      start bigint,
      end_time bigint,
      action string,
      log_status string
    )
    PARTITIONED BY (dt string)
    ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ' '
    LOCATION 's3://${aws_s3_bucket.flow_logs.id}/AWSLogs/'
    TBLPROPERTIES ("skip.header.line.count"="1");
  EOT
}

# Athena named query — Find rejected traffic (potential attacks)
resource "aws_athena_named_query" "rejected_traffic" {
  name        = "${local.prefix}-rejected-traffic"
  database    = aws_athena_database.flow_logs.name
  description = "Find all rejected traffic — potential security threats"

  query = <<-EOT
    SELECT srcaddr, dstaddr, dstport, protocol, action, SUM(packets) as total_packets
    FROM vpc_flow_logs
    WHERE action = 'REJECT'
    GROUP BY srcaddr, dstaddr, dstport, protocol, action
    ORDER BY total_packets DESC
    LIMIT 50;
  EOT
}

# Athena named query — Top talkers (bandwidth consumers)
resource "aws_athena_named_query" "top_talkers" {
  name        = "${local.prefix}-top-talkers"
  database    = aws_athena_database.flow_logs.name
  description = "Find top bandwidth consumers"

  query = <<-EOT
    SELECT srcaddr, dstaddr, SUM(bytes) as total_bytes, SUM(packets) as total_packets
    FROM vpc_flow_logs
    WHERE action = 'ACCEPT'
    GROUP BY srcaddr, dstaddr
    ORDER BY total_bytes DESC
    LIMIT 25;
  EOT
}

# Athena named query — SSH brute force detection
resource "aws_athena_named_query" "ssh_attempts" {
  name        = "${local.prefix}-ssh-attempts"
  database    = aws_athena_database.flow_logs.name
  description = "Detect potential SSH brute force attacks"

  query = <<-EOT
    SELECT srcaddr, dstaddr, COUNT(*) as attempt_count
    FROM vpc_flow_logs
    WHERE dstport = 22
      AND action = 'REJECT'
    GROUP BY srcaddr, dstaddr
    HAVING COUNT(*) > 10
    ORDER BY attempt_count DESC;
  EOT
}

# =============================================================================
# CLOUDWATCH LOGS INSIGHTS — Real-Time Log Queries
# =============================================================================
# CloudWatch Insights queries run against flow logs in CloudWatch in real-time.
# Unlike Athena (which queries S3), these are faster for recent data.

# We store these as Athena named queries for reference, but you would
# run them in the CloudWatch Logs Insights console.

# Example queries (documented for the deliverable):
#
# 1. Top 10 rejected source IPs (last hour):
#    fields @timestamp, srcAddr, dstAddr, dstPort, action
#    | filter action = "REJECT"
#    | stats count(*) as rejections by srcAddr
#    | sort rejections desc
#    | limit 10
#
# 2. Traffic by port:
#    fields @timestamp, dstPort, action
#    | stats count(*) as requests by dstPort, action
#    | sort requests desc
#    | limit 20
#
# 3. Unusual large data transfers:
#    fields @timestamp, srcAddr, dstAddr, bytes
#    | filter bytes > 1000000
#    | sort bytes desc
#    | limit 25

# =============================================================================
# CLOUDWATCH ALARMS — Automated Alerts for Unusual Traffic
# =============================================================================

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name = "${local.prefix}-security-alerts"

  tags = {
    Name = "${local.prefix}-security-alerts"
  }
}

# --- Metric Filter: Count rejected packets in production ---
# This extracts a custom metric from flow log data in CloudWatch
resource "aws_cloudwatch_log_metric_filter" "rejected_packets" {
  name           = "${local.prefix}-rejected-packets"
  log_group_name = aws_cloudwatch_log_group.flow_logs_production.name
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes, start, end, action=\"REJECT\", log_status]"

  metric_transformation {
    name          = "RejectedPacketCount"
    namespace     = "${local.prefix}/VPCFlowLogs"
    value         = "$packets"
    default_value = "0"
  }
}

# Alarm: too many rejected packets (potential DDoS or port scan)
resource "aws_cloudwatch_metric_alarm" "high_rejected_traffic" {
  alarm_name          = "${local.prefix}-high-rejected-traffic"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RejectedPacketCount"
  namespace           = "${local.prefix}/VPCFlowLogs"
  period              = 300  # 5 minutes
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "High number of rejected packets detected — possible port scan or DDoS"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = {
    Name = "${local.prefix}-high-rejected-traffic-alarm"
  }
}

# --- Metric Filter: SSH connection attempts ---
resource "aws_cloudwatch_log_metric_filter" "ssh_attempts" {
  name           = "${local.prefix}-ssh-attempts"
  log_group_name = aws_cloudwatch_log_group.flow_logs_production.name
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport=22, protocol=6, packets, bytes, start, end, action, log_status]"

  metric_transformation {
    name          = "SSHAttemptCount"
    namespace     = "${local.prefix}/VPCFlowLogs"
    value         = "1"
    default_value = "0"
  }
}

# Alarm: unusual SSH activity
resource "aws_cloudwatch_metric_alarm" "ssh_brute_force" {
  alarm_name          = "${local.prefix}-ssh-brute-force"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SSHAttemptCount"
  namespace           = "${local.prefix}/VPCFlowLogs"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "High SSH connection attempts detected — possible brute force attack"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = {
    Name = "${local.prefix}-ssh-brute-force-alarm"
  }
}

# --- Network Firewall alert count alarm ---
resource "aws_cloudwatch_log_metric_filter" "firewall_alerts" {
  name           = "${local.prefix}-firewall-alerts"
  log_group_name = aws_cloudwatch_log_group.firewall_alert.name
  pattern        = "{ $.event_type = \"alert\" }"

  metric_transformation {
    name          = "FirewallAlertCount"
    namespace     = "${local.prefix}/NetworkFirewall"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "firewall_alert_spike" {
  alarm_name          = "${local.prefix}-firewall-alert-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FirewallAlertCount"
  namespace           = "${local.prefix}/NetworkFirewall"
  period              = 300
  statistic           = "Sum"
  threshold           = 20
  alarm_description   = "Spike in Network Firewall alerts — review blocked traffic"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = {
    Name = "${local.prefix}-firewall-alert-spike-alarm"
  }
}
