# Network Architecture Diagram

## High-Level Multi-VPC Architecture

```
                         ┌─────────────────────────────────┐
                         │       ON-PREMISES NETWORK       │
                         │        192.168.0.0/16           │
                         │    ┌─────────────────────┐      │
                         │    │  Customer Gateway    │      │
                         │    │  (Router/Firewall)   │      │
                         │    └─────────┬───────────┘      │
                         └──────────────┼──────────────────┘
                                        │
                              IPsec VPN Tunnel
                              (Encrypted over Internet)
                                        │
┌───────────────────────────────────────┼──────────────────────────────────────┐
│                              AWS CLOUD                                       │
│                                       │                                      │
│                         ┌─────────────┴───────────────┐                      │
│                         │      TRANSIT GATEWAY         │                      │
│                         │   (Central Hub Router)       │                      │
│                         │                              │                      │
│                         │  ┌──────────────────────┐    │                      │
│                         │  │  TGW Route Tables:    │    │                      │
│                         │  │  - Production RT      │    │                      │
│                         │  │  - Staging RT         │    │                      │
│                         │  │  - Shared Services RT │    │                      │
│                         │  │  - VPN RT             │    │                      │
│                         │  └──────────────────────┘    │                      │
│                         └──┬──────────┬──────────┬─────┘                      │
│                            │          │          │                            │
│            ┌───────────────┘          │          └───────────────┐            │
│            │                          │                          │            │
│  ┌─────────┴──────────┐  ┌───────────┴─────────┐  ┌────────────┴─────────┐  │
│  │  PRODUCTION VPC     │  │  STAGING VPC         │  │  SHARED SERVICES VPC │  │
│  │  10.1.0.0/16        │  │  10.2.0.0/16         │  │  10.3.0.0/16         │  │
│  │                     │  │                      │  │                      │  │
│  │  ┌───────────────┐  │  │  ┌───────────────┐   │  │  ┌───────────────┐   │  │
│  │  │ Public Subnet │  │  │  │ Public Subnet │   │  │  │ Public Subnet │   │  │
│  │  │ 10.1.1.0/24   │  │  │  │ 10.2.1.0/24   │   │  │  │ 10.3.1.0/24   │   │  │
│  │  │ 10.1.2.0/24   │  │  │  │ 10.2.2.0/24   │   │  │  │ 10.3.2.0/24   │   │  │
│  │  │  [IGW] [NAT]  │  │  │  │  [IGW] [NAT]  │   │  │  │  [IGW] [NAT]  │   │  │
│  │  └───────────────┘  │  │  └───────────────┘   │  │  └───────────────┘   │  │
│  │                     │  │                      │  │                      │  │
│  │  ┌───────────────┐  │  │  ┌───────────────┐   │  │  ┌───────────────┐   │  │
│  │  │ Private Subnet│  │  │  │ Private Subnet│   │  │  │ Private Subnet│   │  │
│  │  │ 10.1.10.0/24  │  │  │  │ 10.2.10.0/24  │   │  │  │ 10.3.10.0/24  │   │  │
│  │  │ 10.1.20.0/24  │  │  │  │ 10.2.20.0/24  │   │  │  │ 10.3.20.0/24  │   │  │
│  │  │ [App] [DB]    │  │  │  │ [App] [DB]    │   │  │  │ [NLB] [Logs]  │   │  │
│  │  └───────────────┘  │  │  └───────────────┘   │  │  └───────────────┘   │  │
│  │                     │  │                      │  │                      │  │
│  │  ┌───────────────┐  │  │                      │  │  VPC Endpoints:      │  │
│  │  │ Firewall Sub  │  │  │                      │  │  - S3 (Gateway)      │  │
│  │  │ [AWS Network  │  │  │                      │  │  - CloudWatch Logs   │  │
│  │  │  Firewall]    │  │  │                      │  │  - SSM               │  │
│  │  └───────────────┘  │  │                      │  │  - EC2 Messages      │  │
│  │                     │  │                      │  │                      │  │
│  │  Security Layers:   │  │                      │  │  PrivateLink Service │  │
│  │  - Security Groups  │  │                      │  │  (NLB + Endpoint Svc)│  │
│  │  - NACLs            │  │                      │  │                      │  │
│  │  - Network Firewall │  │                      │  │                      │  │
│  └─────────────────────┘  └──────────────────────┘  └──────────────────────┘  │
│                                                                              │
│  MONITORING:                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐     │
│  │  VPC Flow Logs → CloudWatch Logs (real-time) + S3 (Athena queries)  │     │
│  │  Network Firewall Logs → CloudWatch (alerts + flow)                 │     │
│  │  CloudWatch Alarms → SNS → (Email/Slack/PagerDuty)                  │     │
│  │  Traffic Mirroring → NLB → IDS/IPS inspection                       │     │
│  └──────────────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Traffic Flow Patterns

```
1. Internet → Production (inbound web traffic):
   Internet → IGW → Network Firewall → Public Subnet (ALB) → Private Subnet (App)

2. Production → Shared Services (internal service call):
   Prod Private Subnet → TGW → Shared Services Private Subnet

3. On-Premises → AWS (hybrid connectivity):
   On-Prem Router → VPN Tunnel → TGW → Any VPC Private Subnet

4. Production → S3 (private access):
   Prod Private Subnet → S3 Gateway Endpoint → S3 (never touches internet)

5. Production → Shared Service (PrivateLink):
   Prod Private Subnet → Interface Endpoint → PrivateLink → Shared Services NLB
```
