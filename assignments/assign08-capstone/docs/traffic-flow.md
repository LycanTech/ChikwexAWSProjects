# Traffic Flow Documentation

## Project: chikwex — Multi-VPC Enterprise Network

---

## 1. Internet to Production Web Server

```
User Browser
    │
    ▼ (HTTPS request)
Internet Gateway (chikwex-production-igw)
    │
    ▼ (Public route table routes to IGW)
AWS Network Firewall (chikwex-production-firewall)
    │  - Inspects TLS SNI (domain name)
    │  - Checks against Suricata rules
    │  - Blocks known malicious domains
    │  - Logs to CloudWatch
    ▼
Public Subnet (10.1.1.0/24)
    │  NACL Check: Allow HTTP/HTTPS inbound ✓
    │  Security Group Check: Allow port 443 from 0.0.0.0/0 ✓
    ▼
Web Server (EC2 in public subnet)
    │
    ▼ (Internal request on port 8080)
Private Subnet (10.1.10.0/24)
    │  Security Group Check: Allow port 8080 from web-sg only ✓
    ▼
App Server (EC2 in private subnet)
    │
    ▼ (MySQL query on port 3306)
    │  Security Group Check: Allow port 3306 from app-sg only ✓
    ▼
Database Server (RDS in private subnet)
```

**Security checks passed:** Network Firewall → NACL → Security Group (3 layers)

---

## 2. Production App Server Accessing S3

```
App Server (10.1.10.x in private subnet)
    │
    ▼ (AWS SDK call to S3)
Production Private Route Table
    │  Route: S3 prefix list → S3 Gateway Endpoint
    │  (Traffic NEVER leaves AWS network)
    ▼
S3 Gateway Endpoint (chikwex-production-s3-endpoint)
    │
    ▼
Amazon S3 (private connection)
```

**Key point:** No NAT Gateway needed. No internet traversal. Free endpoint.

---

## 3. Production to Shared Services (via Transit Gateway)

```
App Server (10.1.10.x in Production VPC)
    │
    ▼ (Request to 10.3.10.x)
Production Private Route Table
    │  Route: 10.3.0.0/16 → Transit Gateway
    ▼
Transit Gateway (chikwex-transit-gateway)
    │  TGW Route Table (Production RT):
    │    10.3.0.0/16 → Shared Services Attachment ✓
    │    (10.2.0.0/16 → NOT present — staging blocked)
    ▼
Shared Services VPC Attachment
    │
    ▼
Shared Services Private Subnet (10.3.10.x)
    │  Security Group Check on destination resource ✓
    ▼
Shared Service (Monitoring/Logging/DNS)
```

**Key point:** Production can reach Shared Services but NOT Staging. Enforced at TGW route table level.

---

## 4. Production to Shared Service via PrivateLink

```
App Server (10.1.10.x in Production VPC)
    │
    ▼ (Request to PrivateLink endpoint)
Interface Endpoint (chikwex-production-shared-service-endpoint)
    │  Creates ENI in Production private subnet
    │  Security Group: Allow port 80 from prod CIDR ✓
    │
    ▼ (AWS PrivateLink — private AWS backbone)
VPC Endpoint Service (chikwex-shared-endpoint-service)
    │
    ▼
Network Load Balancer (chikwex-shared-nlb)
    │  Internal NLB in Shared Services private subnet
    ▼
Target Group → Backend Service
```

**Key point:** Traffic never traverses the Transit Gateway or internet. PrivateLink is a direct private connection.

---

## 5. On-Premises to AWS (Site-to-Site VPN)

```
On-Prem Server (192.168.1.x)
    │
    ▼
Corporate Router/Firewall (Customer Gateway)
    │  BGP ASN: 65000
    │  Public IP: 203.0.113.1
    ▼
IPsec VPN Tunnel (Encrypted, 2 tunnels for HA)
    │  AES-256 encryption
    │  Over public internet
    ▼
Transit Gateway (chikwex-transit-gateway)
    │  VPN Attachment
    │  TGW Route Table: 10.1.0.0/16, 10.2.0.0/16, 10.3.0.0/16
    ▼
Any VPC Private Subnet
    │  VPC Route Table: 192.168.0.0/16 → TGW
    │  (Return traffic routes back through TGW → VPN)
    ▼
AWS Resource
```

**Key point:** VPN attached to TGW means on-prem can reach ALL VPCs through a single connection.

---

## 6. VPC Flow Log Data Flow

```
Network Interface (ENI on any instance)
    │
    ▼ (Captures packet metadata)
VPC Flow Log Service
    │
    ├──▶ CloudWatch Logs (real-time)
    │       │
    │       ├──▶ Metric Filters (extract custom metrics)
    │       │       │
    │       │       ▼
    │       │    CloudWatch Alarms
    │       │       │
    │       │       ▼
    │       │    SNS Topic → Email/Slack/PagerDuty
    │       │
    │       └──▶ CloudWatch Logs Insights (ad-hoc queries)
    │
    └──▶ S3 Bucket (long-term storage)
            │
            ▼
         Athena (SQL queries)
            │
            ▼
         Query Results → S3 Results Bucket
```

---

## 7. Traffic Mirroring Data Flow

```
Production EC2 Instance (ENI)
    │
    ▼ (Mirror Session copies packets)
Mirror Filter
    │  Rules: Capture HTTP (80) and HTTPS (443)
    │  Direction: Ingress and Egress
    ▼
Mirror Target (NLB in Shared Services)
    │
    ▼
IDS/IPS Inspection Tool
    │  (e.g., Suricata, Zeek, or commercial IDS)
    ▼
Security Team Dashboard / Alerts
```

**Key point:** Unlike Flow Logs (metadata only), Traffic Mirroring captures full packet payloads for deep content inspection.

---

## 8. Route Table Summary

### Production VPC Private Route Table
| Destination | Target | Purpose |
|------------|--------|---------|
| 10.1.0.0/16 | local | Within-VPC traffic |
| 0.0.0.0/0 | NAT Gateway | Internet access (outbound only) |
| 10.2.0.0/16 | Transit Gateway | To Staging VPC |
| 10.3.0.0/16 | Transit Gateway | To Shared Services VPC |
| 192.168.0.0/16 | Transit Gateway | To On-Premises |
| S3 prefix list | S3 Gateway Endpoint | Private S3 access |

### Transit Gateway Route Tables
| Route Table | Routes | Purpose |
|------------|--------|---------|
| Production RT | 10.3.0.0/16 → Shared Services | Prod can reach shared services |
| Staging RT | 10.3.0.0/16 → Shared Services | Staging can reach shared services |
| Shared Services RT | 10.1.0.0/16 → Production, 10.2.0.0/16 → Staging | Hub can reach both spokes |
| VPN RT | 192.168.0.0/16 → VPN Attachment | On-prem routing |
