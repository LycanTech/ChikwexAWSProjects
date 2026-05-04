# Troubleshooting Guide

## Project: chikwex — Multi-VPC Enterprise Network

---

## 1. VPC Connectivity Issues

### Problem: Instances in different VPCs cannot communicate

**Diagnostic Steps:**
```bash
# 1. Verify Transit Gateway attachments are active
aws ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=state,Values=available" \
  --query "TransitGatewayVpcAttachments[*].[TransitGatewayAttachmentId,VpcId,State]"

# 2. Check TGW route tables for correct routes
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <tgw-rt-id> \
  --filters "Name=type,Values=propagated,static"

# 3. Verify VPC route tables point to TGW
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query "RouteTables[*].Routes[?TransitGatewayId!=null]"
```

**Common Causes:**
- Missing route in VPC route table pointing to TGW for the destination CIDR
- TGW route table missing propagation for the target VPC
- Security Group on destination instance doesn't allow traffic from source CIDR
- NACL blocking traffic (remember NACLs are stateless — check BOTH directions)

**Fix Checklist:**
- [ ] VPC route table has route to destination CIDR via TGW
- [ ] TGW route table has propagation/route for destination attachment
- [ ] Security Group allows inbound from source CIDR/SG
- [ ] NACL allows inbound on required port AND outbound on ephemeral ports (1024-65535)

---

## 2. VPN Connectivity Issues

### Problem: On-premises cannot reach AWS resources

**Diagnostic Steps:**
```bash
# 1. Check VPN tunnel status
aws ec2 describe-vpn-connections \
  --vpn-connection-ids <vpn-id> \
  --query "VpnConnections[*].VgwTelemetry[*].[OutsideIpAddress,Status,StatusMessage]"

# 2. Check for both tunnels (should have 2 for redundancy)
# Status should be "UP" for at least one tunnel

# 3. Verify TGW has route to on-prem CIDR
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <shared-services-tgw-rt-id> \
  --filters "Name=route-search.exact-match,Values=192.168.0.0/16"
```

**Common Causes:**
- VPN tunnel is DOWN — check on-prem router configuration
- Phase 1/Phase 2 IKE negotiation mismatch (encryption, DH group, lifetime)
- On-prem firewall blocking UDP 500 (IKE) or IP protocol 50 (ESP)
- Missing static route on TGW for on-prem CIDR
- VPC route tables missing route to 192.168.0.0/16 via TGW

**Fix Checklist:**
- [ ] At least one VPN tunnel shows status "UP"
- [ ] On-prem router allows UDP 500, UDP 4500, and IP protocol 50
- [ ] IKE parameters match between AWS and on-prem device
- [ ] TGW static route exists for 192.168.0.0/16 → VPN attachment
- [ ] Each VPC private route table has route for 192.168.0.0/16 → TGW

---

## 3. Security Group / NACL Issues

### Problem: Traffic is being blocked unexpectedly

**Diagnostic Steps:**
```bash
# 1. Check VPC Flow Logs for REJECT entries
# CloudWatch Logs Insights query:
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, action
| filter action = "REJECT"
| filter dstAddr = "<target-ip>"
| sort @timestamp desc
| limit 20

# 2. Review Security Group rules
aws ec2 describe-security-groups \
  --group-ids <sg-id> \
  --query "SecurityGroups[*].IpPermissions"

# 3. Review NACL rules (check rule numbers — lowest wins)
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=<subnet-id>" \
  --query "NetworkAcls[*].[NetworkAclId,Entries[*].[RuleNumber,Protocol,RuleAction,CidrBlock,PortRange]]"
```

**Debugging Approach — Layer by Layer:**
1. **Security Group:** Is the inbound rule present? (Stateful — no outbound rule needed for return traffic)
2. **NACL:** Is the inbound rule present? Is the OUTBOUND rule present for ephemeral ports? (Stateless — both directions required)
3. **Route Table:** Does a route exist for the source CIDR?

**Common NACL Gotcha:** NACLs are **stateless**. If you allow inbound HTTP (port 80), you MUST also allow outbound on ephemeral ports (1024-65535) for the response. This is the #1 NACL troubleshooting issue.

---

## 4. VPC Endpoint Issues

### Problem: Cannot reach AWS services via VPC endpoint

**Diagnostic Steps:**
```bash
# 1. Check endpoint status
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query "VpcEndpoints[*].[VpcEndpointId,ServiceName,State]"

# 2. For Gateway Endpoints (S3/DynamoDB) — verify route table association
aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids <vpce-id> \
  --query "VpcEndpoints[*].RouteTableIds"

# 3. For Interface Endpoints — verify security group allows HTTPS (443)
aws ec2 describe-vpc-endpoints \
  --vpc-endpoint-ids <vpce-id> \
  --query "VpcEndpoints[*].[Groups,SubnetIds,PrivateDnsEnabled]"
```

**Common Causes:**
- **Gateway Endpoint:** Not associated with the correct route table
- **Interface Endpoint:** Security group doesn't allow HTTPS (443) inbound
- **Interface Endpoint:** `private_dns_enabled` is false — SDK still resolving public DNS
- **S3 Endpoint:** Bucket policy restricts access to specific VPC endpoints

---

## 5. Network Firewall Issues

### Problem: Network Firewall blocking legitimate traffic

**Diagnostic Steps:**
```bash
# 1. Check firewall alert logs
# CloudWatch Logs Insights query:
fields @timestamp, event.src_ip, event.dest_ip, event.dest_port, event.alert.signature
| filter event_type = "alert"
| sort @timestamp desc
| limit 20

# 2. Check firewall flow logs for dropped traffic
fields @timestamp, event.src_ip, event.dest_ip, event.app_proto, event.flow.reason
| sort @timestamp desc
| limit 20

# 3. Review firewall rule groups
aws network-firewall describe-rule-group \
  --rule-group-arn <rule-group-arn> \
  --type STATEFUL
```

**Common Causes:**
- Default action is set to drop — traffic not matching any rule gets dropped
- Suricata rule syntax error — rule doesn't match intended traffic
- Rule ordering — Suricata evaluates rules top-down; a drop rule may fire before a pass rule
- Missing DNS (port 53) allow rule — domain-based rules can't resolve

**Fix:** Always ensure DNS (UDP/TCP 53) is explicitly allowed in firewall rules.

---

## 6. Flow Logs Not Appearing

### Problem: VPC Flow Logs are empty or missing

**Diagnostic Steps:**
```bash
# 1. Check flow log status
aws ec2 describe-flow-logs \
  --filter "Name=resource-id,Values=<vpc-id>" \
  --query "FlowLogs[*].[FlowLogId,FlowLogStatus,DeliverLogsStatus]"

# 2. Check IAM role permissions
aws iam get-role-policy \
  --role-name chikwex-flow-logs-role \
  --policy-name chikwex-flow-logs-policy

# 3. For S3 destination — check bucket policy
aws s3api get-bucket-policy --bucket <flow-logs-bucket>
```

**Common Causes:**
- IAM role missing `logs:CreateLogStream` or `logs:PutLogEvents` permission
- CloudWatch Log Group doesn't exist (deleted or wrong name)
- S3 bucket policy doesn't allow flow log delivery
- Flow Log status shows "FAILED" — check DeliverLogsErrorMessage

**Note:** Flow Logs have a 5-10 minute delay before data appears. Don't panic if logs aren't immediate.

---

## 7. PrivateLink Issues

### Problem: Consumer VPC cannot reach PrivateLink service

**Diagnostic Steps:**
```bash
# 1. Check endpoint service status
aws ec2 describe-vpc-endpoint-services \
  --service-names <service-name> \
  --query "ServiceDetails[*].[ServiceName,ServiceState,AcceptanceRequired]"

# 2. Check consumer endpoint status
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=<consumer-vpc-id>" \
  --query "VpcEndpoints[*].[VpcEndpointId,State,ServiceName]"

# 3. Check NLB health
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn>
```

**Common Causes:**
- Endpoint service has `acceptance_required = true` but connection not accepted
- NLB has no healthy targets
- Consumer endpoint security group doesn't allow outbound to the service port
- NLB is in a different AZ than the endpoint

---

## 8. Useful CloudWatch Logs Insights Queries

### Top Rejected IPs (Potential Attackers)
```
fields srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count(*) as rejections by srcAddr
| sort rejections desc
| limit 10
```

### Traffic Volume by Port
```
fields dstPort, action, bytes
| stats sum(bytes) as total_bytes, count(*) as connections by dstPort, action
| sort total_bytes desc
| limit 20
```

### Cross-VPC Traffic via TGW
```
fields srcAddr, dstAddr, bytes, action
| filter (srcAddr like /^10\.1\./ and dstAddr like /^10\.3\./)
   or (srcAddr like /^10\.3\./ and dstAddr like /^10\.1\./)
| stats sum(bytes) as total_bytes by srcAddr, dstAddr
| sort total_bytes desc
```

### Detect Port Scanning
```
fields srcAddr, dstPort, action
| filter action = "REJECT"
| stats count(dstPort) as ports_attempted by srcAddr
| filter ports_attempted > 20
| sort ports_attempted desc
```
