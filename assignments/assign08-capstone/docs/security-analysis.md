# Security Analysis Report

## Project: chikwex — Multi-VPC Enterprise Network

---

## 1. Security Architecture Overview

This architecture implements **defense in depth** with three distinct security layers, each operating at a different network level to ensure no single point of failure in security controls.

### Layer 1: Security Groups (Instance Level — Stateful)

| Security Group | VPC | Inbound Rules | Purpose |
|---------------|-----|---------------|---------|
| `chikwex-production-web-sg` | Production | HTTP (80), HTTPS (443) from 0.0.0.0/0 | Public-facing web servers |
| `chikwex-production-app-sg` | Production | Port 8080 from web SG only | Application tier — no direct external access |
| `chikwex-production-db-sg` | Production | MySQL (3306) from app SG only | Database tier — only app servers can connect |
| `chikwex-shared-services-bastion-sg` | Shared Services | SSH (22) from on-prem CIDR only | Bastion host for admin access |
| `chikwex-shared-services-vpce-sg` | Shared Services | HTTPS (443) from all VPC CIDRs | VPC interface endpoints |
| `chikwex-production-privatelink-sg` | Production | Port 80 from prod CIDR | PrivateLink consumer endpoint |

**Key Security Principle:** Security groups follow the **principle of least privilege** — each tier only accepts traffic from the tier directly above it (Web → App → DB chain).

### Layer 2: Network ACLs (Subnet Level — Stateless)

| NACL | Applied To | Key Rules |
|------|-----------|-----------|
| Production Private NACL | Private subnets | Allow inbound from VPC, Shared Services, and on-prem CIDRs. Allow ephemeral ports for NAT return traffic. |
| Production Public NACL | Public subnets | Allow inbound HTTP/HTTPS and ephemeral ports only. |

**Key Security Principle:** NACLs provide a **subnet-level perimeter** that operates independently of security groups. Even if a security group is misconfigured, NACLs block unauthorized traffic.

### Layer 3: AWS Network Firewall (VPC Level — Deep Packet Inspection)

| Component | Details |
|-----------|---------|
| Firewall Location | Production VPC (dedicated firewall subnets) |
| Rule Engine | Suricata-compatible stateful rules |
| Blocked | Known malicious domains (TLS SNI inspection) |
| Allowed | HTTPS (443), HTTP (80), DNS (53) outbound |
| Logging | Alert logs + Flow logs → CloudWatch |

**Key Security Principle:** Network Firewall provides **deep packet inspection** and can block traffic based on domain names, protocols, and patterns — capabilities that Security Groups and NACLs lack.

---

## 2. Network Segmentation Analysis

### VPC Isolation Strategy

| Source | Destination | Allowed? | Mechanism |
|--------|-------------|----------|-----------|
| Production | Shared Services | Yes | Transit Gateway |
| Staging | Shared Services | Yes | Transit Gateway |
| Production | Staging | Blocked at TGW RT | TGW route table isolation |
| Staging | Production | Blocked at TGW RT | TGW route table isolation |
| On-Premises | All VPCs | Yes | VPN → TGW |
| Internet | Production Public | Yes (HTTP/S only) | IGW + SG + NACL + Firewall |
| Internet | Private Subnets | No | No IGW route in private RT |

**Critical Design Decision:** Production and Staging cannot communicate directly. This prevents staging test data or misconfigurations from affecting production. Both can reach Shared Services for centralized tooling.

### VPC Endpoint Security

| Endpoint | Type | Security Benefit |
|----------|------|-----------------|
| S3 Gateway | Gateway | Traffic never leaves AWS network. No internet exposure. Free. |
| CloudWatch Logs | Interface | Log shipping stays private. No NAT needed. |
| SSM | Interface | Instance management without SSH or internet access |
| EC2 Messages | Interface | Session Manager works in fully private subnets |

---

## 3. Encryption in Transit

| Traffic Path | Encryption | Method |
|-------------|-----------|--------|
| On-Prem → AWS | Encrypted | IPsec VPN (AES-256) |
| VPC → S3 | Encrypted | HTTPS via VPC endpoint |
| VPC → CloudWatch | Encrypted | HTTPS via interface endpoint |
| Inter-VPC (via TGW) | AWS network | Traffic stays on AWS backbone |
| PrivateLink | AWS network | Never traverses public internet |

---

## 4. Monitoring & Threat Detection

| Monitoring Layer | Data Captured | Storage | Alert Mechanism |
|-----------------|---------------|---------|-----------------|
| VPC Flow Logs | IP metadata (src, dst, port, action) | CloudWatch + S3 | Metric filters → Alarms |
| Network Firewall Logs | Deep packet alerts, flow data | CloudWatch | Alert count alarms |
| Traffic Mirroring | Full packet capture | NLB → IDS/IPS | External analysis tools |
| Athena Queries | Historical flow log analysis | S3 query results | On-demand investigation |

### Automated Alerts

| Alert | Trigger | Threshold |
|-------|---------|-----------|
| High Rejected Traffic | Rejected packet count | > 1000 packets / 5 min |
| SSH Brute Force | SSH connection attempts | > 50 attempts / 5 min |
| Firewall Alert Spike | Network Firewall alerts | > 20 alerts / 5 min |

---

## 5. Risk Assessment

| Risk | Mitigation | Residual Risk |
|------|-----------|---------------|
| DDoS Attack | Network Firewall + NACL rate limiting + CloudWatch alerts | Medium — consider AWS Shield Advanced for production |
| Lateral Movement | VPC segmentation + SG chaining (web→app→db) | Low |
| Data Exfiltration | VPC endpoints keep traffic private; Network Firewall inspects outbound | Low |
| SSH Brute Force | Bastion SG restricts to on-prem; CloudWatch alarm detects spikes | Low |
| Misconfigured SG | NACLs provide independent backup layer | Low |
| VPN Compromise | IPsec encryption; TGW route isolation | Medium — consider Direct Connect for higher security |

---

## 6. Recommendations for Production Hardening

1. **Enable AWS Shield Advanced** — DDoS protection with 24/7 response team
2. **Add AWS WAF** — Web Application Firewall in front of ALBs for OWASP protection
3. **Enable GuardDuty** — AI-powered threat detection across all VPCs
4. **Use AWS Config Rules** — Continuously audit security group and NACL compliance
5. **Implement Direct Connect** — Replace VPN with dedicated private connection for higher bandwidth and security
6. **Enable S3 bucket logging** — Audit access to flow log storage
7. **Add VPN redundancy** — Second VPN connection for failover
