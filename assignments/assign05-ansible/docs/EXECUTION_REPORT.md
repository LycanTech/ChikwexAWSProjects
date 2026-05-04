# Playbook Execution Report

## Assignment 5: Infrastructure Automation with Ansible

**Project:** Chikwex Infrastructure
**Date:** January 2026
**Author:** Chikwe Azinge

---

## Executive Summary

This report documents the implementation of a comprehensive Ansible automation framework for AWS infrastructure management. The solution provides idempotent, tested, and CI/CD-integrated infrastructure-as-code for deploying and managing web servers, database servers, and application workloads.

---

## 1. Dynamic Inventory Configuration

### Implementation Details

| Component | Description |
|-----------|-------------|
| Plugin | `amazon.aws.aws_ec2` |
| Environments | Development, Production |
| Grouping | By tags, instance type, AZ, role |
| Caching | JSON file cache, 5-minute TTL |

### Configuration Files

- `inventories/dev/aws_ec2.yml` - Development dynamic inventory
- `inventories/prod/aws_ec2.yml` - Production dynamic inventory (multi-region)
- `inventories/dev/hosts.yml` - Static fallback inventory
- `scripts/custom_inventory.py` - Custom inventory script with SSM integration

### Tag-based Grouping

```
Instance Tags          →  Ansible Groups
─────────────────────────────────────────
Role=webserver         →  webservers, role_webserver
Role=database          →  dbservers, role_database
Environment=dev        →  env_dev
Environment=prod       →  env_prod
```

### Verification Command

```bash
ansible-inventory -i inventories/dev/aws_ec2.yml --graph
```

---

## 2. Playbook Development

### Master Playbook Structure

```
site.yml
├── Common configuration (all hosts)
│   ├── common role
│   ├── security role
│   └── aws_integration role
├── webservers.yml (import)
└── dbservers.yml (import)
```

### Playbook Matrix

| Playbook | Target Hosts | Roles Applied | Purpose |
|----------|--------------|---------------|---------|
| site.yml | all | common, security, aws_integration | Master orchestration |
| webservers.yml | webservers | nginx | Web server config |
| dbservers.yml | dbservers | postgresql | Database setup |
| deploy.yml | appservers | app_deploy | Application deployment |

### Execution Examples

```bash
# Full infrastructure
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml

# Web servers only
ansible-playbook playbooks/webservers.yml -i inventories/dev/aws_ec2.yml

# With tags
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml --tags "nginx,security"
```

---

## 3. Roles and Structure

### Role Inventory

| Role | Purpose | Dependencies | Key Features |
|------|---------|--------------|--------------|
| common | Base system config | None | Packages, users, SSH, NTP |
| nginx | Web server | common | SSL, vhosts, upstream |
| postgresql | Database | common | Replication, backup |
| security | Hardening | common | Firewall, fail2ban, audit |
| aws_integration | AWS services | common | SSM, CloudWatch, Secrets |
| app_deploy | Deployment | common | Git/artifact, zero-downtime |

### Standard Role Structure

```
roles/<role_name>/
├── tasks/
│   └── main.yml
├── handlers/
│   └── main.yml
├── templates/
│   └── *.j2
├── defaults/
│   └── main.yml
├── vars/
│   └── main.yml (OS-specific)
├── meta/
│   └── main.yml
└── molecule/
    └── default/
```

### Role Dependencies

```
app_deploy
    └── common

nginx
    └── common

postgresql
    └── common

security
    └── common

aws_integration
    └── common
```

---

## 4. Variables and Secrets Management

### Variable Hierarchy

```
group_vars/all/main.yml          (lowest priority)
group_vars/all/vault.yml         (encrypted)
group_vars/webservers/main.yml
group_vars/dbservers/main.yml
host_vars/<hostname>.yml         (highest priority)
```

### Vault-Protected Secrets

| Variable | Description |
|----------|-------------|
| vault_aws_account_id | AWS account identifier |
| vault_postgresql_admin_password | Database admin password |
| vault_ssl_certificate | SSL certificate content |
| vault_ssl_private_key | SSL private key |
| vault_app_secret_key | Application secret key |

### Vault Operations

```bash
# Encrypt
ansible-vault encrypt group_vars/all/vault.yml

# Edit
ansible-vault edit group_vars/all/vault.yml

# Run with vault
ansible-playbook site.yml --vault-password-file .vault_pass
```

---

## 5. AWS Integration

### Systems Manager (SSM)

- SSM Agent installed and configured
- Session Manager support for SSH-less access
- Run Command integration capability

### CloudWatch Integration

| Component | Configuration |
|-----------|---------------|
| Metrics | CPU, memory, disk, network |
| Logs | /var/log/messages, /var/log/secure, nginx, postgresql |
| Namespace | Chikwex/EC2 |
| Interval | 60 seconds |

### Secrets Manager

- Automatic secret retrieval script deployed
- Credentials cached locally with secure permissions
- Refresh cron job for automatic updates

---

## 6. Idempotency Verification

### Idempotent Task Patterns Used

| Pattern | Example |
|---------|---------|
| State declarations | `state: present`, `state: started` |
| Template with backup | `backup: true` |
| File with creates | `creates: /path/to/file` |
| Conditional execution | `when: condition` |
| Changed_when override | `changed_when: false` |

### Handler Usage

```yaml
handlers:
  - name: Restart nginx
    ansible.builtin.service:
      name: nginx
      state: restarted
```

### Idempotency Test

```bash
# Run twice - second run should show 0 changed
ansible-playbook site.yml -i inventories/dev/aws_ec2.yml
ansible-playbook site.yml -i inventories/dev/aws_ec2.yml
```

---

## 7. Testing Implementation

### Molecule Configuration

| Platform | Image | Groups |
|----------|-------|--------|
| amazonlinux2023 | amazonlinux:2023 | webservers |
| rockylinux9 | rockylinux:9 | dbservers |
| ubuntu2204 | ubuntu:22.04 | webservers |

### Test Sequence

1. Dependency installation
2. Lint checks
3. Destroy previous instances
4. Syntax validation
5. Create test instances
6. Prepare instances
7. **Converge** (apply roles)
8. **Idempotence** test
9. **Verify** (validation tests)
10. Cleanup

### Running Tests

```bash
# Full test cycle
molecule test

# Quick iteration
molecule converge
molecule verify

# Debug mode
molecule --debug test
```

---

## 8. CI/CD Pipeline

### Workflow Stages

```
┌─────────────┐    ┌─────────────────┐    ┌──────────────┐
│    Lint     │───►│  Molecule Test  │───►│ Security Scan│
└─────────────┘    └─────────────────┘    └──────────────┘
                            │
                            ▼
              ┌───────────────────────────┐
              │  Deploy to Development    │
              └───────────────────────────┘
                            │
                            ▼
              ┌───────────────────────────┐
              │ Deploy to Production      │
              │ (Manual Approval Required)│
              └───────────────────────────┘
```

### GitHub Actions Jobs

| Job | Trigger | Actions |
|-----|---------|---------|
| lint | All pushes/PRs | yamllint, ansible-lint, syntax check |
| molecule-test | After lint | Parallel role testing |
| security-scan | After lint | Secret detection |
| deploy-dev | develop branch | Auto-deploy to dev |
| deploy-prod | main + approval | Deploy to production |

---

## 9. Sample Execution Output

### Successful Run

```
PLAY [Apply common configuration to all hosts] *********************************

TASK [Gathering Facts] *********************************************************
ok: [web-dev-01]
ok: [db-dev-01]

TASK [common : Set timezone] ***************************************************
ok: [web-dev-01]
ok: [db-dev-01]

TASK [common : Install common packages] ****************************************
changed: [web-dev-01]
changed: [db-dev-01]

TASK [security : Install fail2ban] *********************************************
changed: [web-dev-01]
changed: [db-dev-01]

TASK [nginx : Install Nginx] ***************************************************
changed: [web-dev-01]

TASK [postgresql : Install PostgreSQL] *****************************************
changed: [db-dev-01]

PLAY RECAP *********************************************************************
web-dev-01                 : ok=45   changed=12   unreachable=0    failed=0
db-dev-01                  : ok=52   changed=15   unreachable=0    failed=0
```

---

## 10. Deliverables Summary

### Completed Items

| Deliverable | Status | Location |
|-------------|--------|----------|
| Dynamic Inventory | ✅ Complete | `inventories/*/aws_ec2.yml` |
| Playbooks | ✅ Complete | `playbooks/` |
| Roles (6) | ✅ Complete | `roles/` |
| Variables/Vault | ✅ Complete | `group_vars/`, `host_vars/` |
| AWS Integration | ✅ Complete | `roles/aws_integration/` |
| Molecule Tests | ✅ Complete | `molecule/` |
| CI/CD Pipeline | ✅ Complete | `.github/workflows/` |
| Documentation | ✅ Complete | `docs/` |

### File Count

```
Total files created: 75+
  - Task files: 30
  - Template files: 25
  - Variable files: 10
  - Configuration files: 10
```

---

## 11. Best Practices Implemented

1. **Role-based organization** - Modular, reusable components
2. **Idempotent tasks** - Safe to run multiple times
3. **Handlers for restarts** - Efficient service management
4. **Vault for secrets** - Secure credential storage
5. **Dynamic inventory** - Automatic host discovery
6. **Tag-based filtering** - Flexible playbook execution
7. **Molecule testing** - Automated role validation
8. **CI/CD integration** - Continuous deployment pipeline
9. **Documentation** - Comprehensive usage guides
10. **Security hardening** - Defense-in-depth approach

---

## 12. Recommendations

### Future Improvements

1. Add AWX/Tower integration for GUI-based execution
2. Implement Ansible Callback plugins for enhanced logging
3. Add Prometheus/Grafana integration for metrics
4. Create role for Kubernetes deployment
5. Implement blue-green deployment strategy

### Maintenance Tasks

- Review and update Ansible collections quarterly
- Rotate vault passwords every 90 days
- Update AMI references for security patches
- Review and prune old releases monthly

---

**Report Generated:** January 2026
**Ansible Version:** 2.14+
**Python Version:** 3.11
