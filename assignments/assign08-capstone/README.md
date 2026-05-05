# CapStone 8 — Network Security and VPC Architecture

## Project: chikwex — Secure Multi-VPC Enterprise Network

### Overview

This project designs and implements a secure multi-VPC architecture for enterprise workloads using Terraform. It demonstrates core AWS networking concepts including VPC design, Transit Gateway, VPN connectivity, VPC endpoints, network security (layered defense), and comprehensive monitoring.

---

## Architecture Summary

```
On-Premises (192.168.0.0/16)
        │
   IPsec VPN Tunnel
        │
   Transit Gateway (Hub)
    ┌───┼───┐
    │   │   │
 Prod Stag Shared
 VPC  VPC  Services
10.1  10.2  10.3
```

**Three VPCs** connected via a Transit Gateway hub:

| VPC | CIDR | Purpose |
|-----|------|---------|
| Production | 10.1.0.0/16 | Live workloads with Network Firewall |
| Staging | 10.2.0.0/16 | Pre-production testing |
| Shared Services | 10.3.0.0/16 | Centralized logging, monitoring, DNS |

**Key design decision:** Production and Staging are isolated from each other at the Transit Gateway level. Both can reach Shared Services but not each other directly.

---

## Topics Covered

| Requirement | Implementation | Terraform File |
|-------------|---------------|----------------|
| **Multi-VPC Design** | 3 VPCs with non-overlapping CIDRs, public/private subnets across 2 AZs | `vpc.tf` |
| **Transit Gateway** | Central hub connecting all VPCs with isolated route tables | `transit_gateway.tf` |
| **Site-to-Site VPN** | IPsec VPN to simulated on-premises, attached to TGW | `vpn.tf` |
| **VPC Endpoints** | S3 Gateway endpoints (all VPCs), Interface endpoints (CloudWatch, SSM) | `endpoints.tf` |
| **PrivateLink** | NLB-backed service in Shared Services consumed by Production | `endpoints.tf` |
| **Network Firewall** | Suricata-based deep packet inspection in Production VPC | `security.tf` |
| **NACLs** | Stateless subnet-level rules for public and private subnets | `security.tf` |
| **Security Groups** | Stateful instance-level rules (Web → App → DB chain) | `security.tf` |
| **VPC Flow Logs** | All VPCs → CloudWatch (real-time) + S3 (Athena analysis) | `flow_logs.tf` |
| **Traffic Mirroring** | Packet capture filter and NLB mirror target | `flow_logs.tf` |
| **Athena** | SQL queries for flow log analysis (rejected traffic, top talkers, SSH detection) | `monitoring.tf` |
| **CloudWatch Alarms** | Alerts for rejected traffic spikes, SSH brute force, firewall alerts | `monitoring.tf` |

---

## Key Concepts Explained

### VPC (Virtual Private Cloud)
Your own isolated network in AWS. You control the IP range, subnets, routing, and gateways. Each VPC is completely isolated unless explicitly connected.

### Transit Gateway vs VPC Peering
- **VPC Peering:** Direct 1-to-1 connection. Doesn't scale (N VPCs = N*(N-1)/2 connections).
- **Transit Gateway:** Central hub. All VPCs attach to it. Scales to thousands. Enterprise standard.

### Defense in Depth (3 Security Layers)
1. **Security Groups** (Instance level, stateful) — locks on each door
2. **NACLs** (Subnet level, stateless) — guards on each floor
3. **Network Firewall** (VPC level, deep inspection) — security checkpoint at the building entrance

### VPC Endpoints vs PrivateLink
- **VPC Endpoints:** Access AWS services (S3, CloudWatch) without internet
- **PrivateLink:** Expose YOUR services from one VPC to another privately

### Flow Logs vs Traffic Mirroring
- **Flow Logs:** Metadata only (who talked to whom, on what port)
- **Traffic Mirroring:** Full packet capture (actual content)

---

## Project Structure

```
NehasCapStone8/
├── README.md                          # This file
├── Assignment8.txt                    # Assignment requirements
├── terraform/
│   ├── providers.tf                   # AWS provider and default tags
│   ├── variables.tf                   # All configurable variables
│   ├── locals.tf                      # Naming conventions (chikwex prefix)
│   ├── vpc.tf                         # 3 VPCs with subnets, IGWs, NATs, route tables
│   ├── transit_gateway.tf             # TGW, attachments, route tables, propagation
│   ├── vpn.tf                         # Site-to-Site VPN (Customer Gateway + VPN Connection)
│   ├── endpoints.tf                   # VPC Endpoints (Gateway + Interface) and PrivateLink
│   ├── security.tf                    # Network Firewall, NACLs, Security Groups
│   ├── flow_logs.tf                   # VPC Flow Logs (CW + S3) and Traffic Mirroring
│   ├── monitoring.tf                  # Athena, CloudWatch Insights, Alarms, SNS
│   └── outputs.tf                     # Key resource IDs and ARNs
└── docs/
    ├── architecture-diagram.md        # Network architecture diagram (ASCII)
    ├── security-analysis.md           # Security analysis report
    ├── traffic-flow.md                # Detailed traffic flow documentation
    └── troubleshooting-guide.md       # Troubleshooting guide with CLI commands
```

---

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- AWS account with permissions for VPC, TGW, VPN, Network Firewall, CloudWatch, S3, Athena

---

## Deployment

```bash
cd terraform

# Initialize Terraform (downloads AWS provider)
terraform init

# Preview what will be created
terraform plan

# Deploy the infrastructure
terraform apply

# When done — destroy all resources to avoid charges
terraform destroy
```

---

## Deliverables

| Deliverable | Location |
|------------|----------|
| Network architecture diagram | [docs/architecture-diagram.md](docs/architecture-diagram.md) |
| Terraform code | [terraform/](terraform/) |
| Security analysis report | [docs/security-analysis.md](docs/security-analysis.md) |
| Traffic flow documentation | [docs/traffic-flow.md](docs/traffic-flow.md) |
| Troubleshooting guide | [docs/troubleshooting-guide.md](docs/troubleshooting-guide.md) |

---

## Resource Naming Convention

All resources use the prefix `chikwex` for easy identification:
- VPCs: `chikwex-production-vpc`, `chikwex-staging-vpc`, `chikwex-shared-services-vpc`
- Subnets: `chikwex-production-public-us-east-1a`
- Transit Gateway: `chikwex-transit-gateway`
- Security Groups: `chikwex-production-web-sg`
- All resources tagged with `Prefix = chikwex` and `Project = chikwex-CapStone8-NetworkSecurity`
