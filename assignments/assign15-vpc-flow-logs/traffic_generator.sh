#!/usr/bin/env bash
# ============================================================
# traffic_generator.sh
# Run this FROM the public EC2 instance after SSH-ing in.
# It generates several traffic patterns so VPC Flow Logs capture
# a variety of ACCEPT and REJECT entries for Athena analysis.
#
# Usage:
#   chmod +x traffic_generator.sh
#   ./traffic_generator.sh <private_ec2_ip>
# ============================================================

set -euo pipefail

PRIVATE_IP="${1:?Usage: $0 <private_ec2_ip>}"

echo "=== [1] Ping between instances (ICMP – protocol 1) ==="
# Generates ICMP flow log entries; ACCEPT because the private SG allows ICMP from VPC
ping -c 10 "$PRIVATE_IP"

echo ""
echo "=== [2] SSH probe to private instance (TCP port 22) ==="
# The private SG does NOT have a port-22 ingress rule, so this will produce
# a REJECT entry in the flow logs – great for demonstrating security analysis.
# We use timeout so the script doesn't hang.
timeout 5 bash -c "echo '' | nc -w 3 $PRIVATE_IP 22" || echo "[expected] Connection refused/timed out – REJECT logged"

echo ""
echo "=== [3] Attempt connection to blocked port 8080 ==="
# Port 8080 is not in the private SG ingress → REJECT in flow logs
timeout 5 bash -c "echo '' | nc -w 3 $PRIVATE_IP 8080" || echo "[expected] Connection refused/timed out – REJECT logged"

echo ""
echo "=== [4] wget external websites from the public instance (TCP, outbound) ==="
# This generates outbound TCP flows through the Internet Gateway
wget -q -O /dev/null https://aws.amazon.com   && echo "aws.amazon.com OK"
wget -q -O /dev/null https://example.com      && echo "example.com OK"
wget -q -O /dev/null https://httpbin.org/get  && echo "httpbin.org OK"

echo ""
echo "=== [5] curl HTTP endpoint (extra TCP traffic) ==="
curl -s -o /dev/null -w "HTTP %{http_code}: httpbin.org\n" http://httpbin.org/ip
curl -s -o /dev/null -w "HTTP %{http_code}: ifconfig.me\n"  http://ifconfig.me/ip

echo ""
echo "=== [6] Flood-ping to generate volume (UDP/ICMP stats) ==="
# Produces enough packets to make the 'top 10 source IPs' query interesting
ping -c 50 "$PRIVATE_IP"

echo ""
echo "=== Done. Wait ~10 minutes, then run Athena queries. ==="
echo "    Flow logs will be in S3 under:"
echo "    AWSLogs/<ACCOUNT_ID>/vpcflowlogs/<REGION>/year=YYYY/month=MM/day=DD/hour=HH/"
