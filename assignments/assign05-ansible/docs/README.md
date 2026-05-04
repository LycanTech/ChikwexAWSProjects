# Chikwex Infrastructure - Ansible Automation

## Assignment 5: Infrastructure Automation with Ansible

This project provides comprehensive infrastructure automation using Ansible for AWS-based infrastructure, including dynamic inventory, role-based configuration, security hardening, and CI/CD integration.

## Table of Contents

- [Project Structure](#project-structure)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Dynamic Inventory](#dynamic-inventory)
- [Roles](#roles)
- [Playbooks](#playbooks)
- [Variables and Vault](#variables-and-vault)
- [Testing](#testing)
- [CI/CD Pipeline](#cicd-pipeline)
- [Execution Examples](#execution-examples)

## Project Structure

```
Chikwex-Infra/
├── ansible.cfg                 # Ansible configuration
├── requirements.yml            # Ansible Galaxy dependencies
├── .yamllint.yml              # YAML linting configuration
├── .github/
│   └── workflows/
│       └── ansible-ci.yml     # GitHub Actions CI/CD
├── docs/
│   └── README.md              # This documentation
├── group_vars/
│   ├── all/
│   │   ├── main.yml           # Global variables
│   │   └── vault.yml          # Encrypted secrets
│   ├── webservers/
│   │   └── main.yml           # Web server variables
│   └── dbservers/
│       └── main.yml           # Database server variables
├── host_vars/
│   └── web-dev-01.yml         # Host-specific overrides
├── inventories/
│   ├── dev/
│   │   ├── aws_ec2.yml        # AWS dynamic inventory (dev)
│   │   └── hosts.yml          # Static inventory fallback
│   └── prod/
│       └── aws_ec2.yml        # AWS dynamic inventory (prod)
├── playbooks/
│   ├── site.yml               # Master playbook
│   ├── webservers.yml         # Web server configuration
│   ├── dbservers.yml          # Database server configuration
│   └── deploy.yml             # Application deployment
├── roles/
│   ├── common/                # Base system configuration
│   ├── nginx/                 # Nginx web server
│   ├── postgresql/            # PostgreSQL database
│   ├── security/              # Security hardening
│   ├── aws_integration/       # AWS services integration
│   └── app_deploy/            # Application deployment
├── molecule/
│   └── default/               # Molecule test configuration
└── scripts/
    └── custom_inventory.py    # Custom inventory script
```

## Requirements

### Control Node
- Python 3.9+
- Ansible 2.14+
- AWS CLI v2
- boto3/botocore

### Managed Nodes
- Amazon Linux 2023 / Amazon Linux 2
- RHEL/CentOS/Rocky Linux 8/9
- Ubuntu 20.04/22.04

### Installation

```bash
# Install Python dependencies
pip install ansible boto3 botocore ansible-lint molecule molecule-plugins[docker]

# Install Ansible collections
ansible-galaxy collection install -r requirements.yml
```

## Quick Start

### 1. Configure AWS Credentials

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
```

### 2. Set Up Vault Password

```bash
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass
```

### 3. Encrypt Sensitive Data

```bash
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file .vault_pass
```

### 4. Run the Playbook

```bash
# Dry run (check mode)
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml --check --diff

# Full run
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml
```

## Dynamic Inventory

### AWS EC2 Dynamic Inventory

The project uses the `amazon.aws.aws_ec2` plugin for automatic host discovery.

**Configuration** (`inventories/dev/aws_ec2.yml`):
- Filters instances by tags: `Environment=dev`, `Project=chikwex-infra`
- Creates groups based on:
  - Instance type (`instance_type_t3_micro`)
  - Availability zone (`az_us_east_1a`)
  - Role tag (`role_webserver`, `role_database`)
  - Environment tag (`env_dev`, `env_prod`)

**Usage:**

```bash
# List all hosts
ansible-inventory -i inventories/dev/aws_ec2.yml --list

# Graph inventory
ansible-inventory -i inventories/dev/aws_ec2.yml --graph
```

### Custom Inventory Script

For advanced scenarios, use the custom Python inventory script:

```bash
# List all hosts
./scripts/custom_inventory.py --list

# Get host variables
./scripts/custom_inventory.py --host web-dev-01
```

## Roles

### common
Base system configuration applied to all hosts:
- Package installation
- User management with SSH keys
- Timezone and NTP configuration
- SSH hardening
- Sysctl tuning
- System limits

### nginx
Web server configuration:
- Nginx installation and configuration
- SSL/TLS setup with Let's Encrypt support
- Virtual host management
- Upstream configuration for load balancing
- Rate limiting and security headers
- Health check endpoints

### postgresql
Database server setup:
- PostgreSQL installation (version configurable)
- Database and user creation
- pg_hba.conf configuration
- Performance tuning
- Backup automation with S3 upload
- Replication support (primary/replica)

### security
Security hardening:
- Firewall configuration (firewalld/ufw)
- Fail2ban with custom jails
- SELinux configuration
- Auditd rules
- Automatic security updates
- System hardening (GRUB, sysctl, etc.)

### aws_integration
AWS services integration:
- SSM Agent configuration
- CloudWatch Agent with custom metrics
- Log shipping to CloudWatch Logs
- Secrets Manager integration
- Instance metadata handling

### app_deploy
Application deployment:
- Git-based deployments
- Artifact-based deployments (URL/S3)
- Zero-downtime releases
- Database migrations
- Systemd service management
- Health check verification

## Playbooks

### site.yml
Master orchestration playbook that applies all roles:
```bash
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml
```

### webservers.yml
Configure web servers only:
```bash
ansible-playbook playbooks/webservers.yml -i inventories/dev/aws_ec2.yml
```

### dbservers.yml
Configure database servers only:
```bash
ansible-playbook playbooks/dbservers.yml -i inventories/dev/aws_ec2.yml
```

### deploy.yml
Deploy applications:
```bash
APP_NAME=myapp APP_VERSION=1.0.0 ansible-playbook playbooks/deploy.yml -i inventories/dev/aws_ec2.yml
```

## Variables and Vault

### Group Variables

| File | Purpose |
|------|---------|
| `group_vars/all/main.yml` | Global settings for all hosts |
| `group_vars/all/vault.yml` | Encrypted secrets (passwords, keys) |
| `group_vars/webservers/main.yml` | Nginx and web-specific settings |
| `group_vars/dbservers/main.yml` | PostgreSQL configuration |

### Vault Operations

```bash
# Encrypt a file
ansible-vault encrypt group_vars/all/vault.yml

# Edit encrypted file
ansible-vault edit group_vars/all/vault.yml

# View encrypted file
ansible-vault view group_vars/all/vault.yml

# Rekey (change password)
ansible-vault rekey group_vars/all/vault.yml
```

## Testing

### Molecule Testing

Run role tests with Molecule:

```bash
# Test specific role
cd roles/common
molecule test

# Test with specific platform
molecule test -s amazonlinux

# Run only converge (skip destroy)
molecule converge
```

### Manual Testing

```bash
# Syntax check
ansible-playbook playbooks/site.yml --syntax-check

# Dry run with diff
ansible-playbook playbooks/site.yml -i inventories/dev/hosts.yml --check --diff

# Run specific tags
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml --tags "common,security"

# Skip specific tags
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml --skip-tags "postgresql"
```

## CI/CD Pipeline

The GitHub Actions workflow provides:

1. **Lint Stage**: YAML linting and ansible-lint
2. **Molecule Tests**: Parallel testing of all roles
3. **Security Scan**: Check for hardcoded secrets
4. **Dev Deployment**: Automatic deployment to development
5. **Prod Deployment**: Manual approval required

### Workflow Triggers

- Push to `main` or `develop` branches
- Pull requests
- Manual dispatch with environment selection

### Required Secrets

Configure these in GitHub repository settings:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `ANSIBLE_VAULT_PASSWORD`
- `AWS_ACCESS_KEY_ID_PROD` (production)
- `AWS_SECRET_ACCESS_KEY_PROD` (production)
- `ANSIBLE_VAULT_PASSWORD_PROD` (production)

## Execution Examples

### Full Infrastructure Deployment

```bash
# Development environment
ansible-playbook playbooks/site.yml \
  -i inventories/dev/aws_ec2.yml \
  --vault-password-file .vault_pass

# Production environment
ansible-playbook playbooks/site.yml \
  -i inventories/prod/aws_ec2.yml \
  --vault-password-file .vault_pass \
  --limit "webservers"
```

### Deploy Application

```bash
# Deploy from Git
ansible-playbook playbooks/deploy.yml \
  -i inventories/dev/aws_ec2.yml \
  -e "app_name=myapp" \
  -e "app_git_repo=https://github.com/org/myapp.git" \
  -e "app_git_branch=release/1.0"

# Deploy from S3 artifact
ansible-playbook playbooks/deploy.yml \
  -i inventories/dev/aws_ec2.yml \
  -e "app_name=myapp" \
  -e "app_version=1.0.0" \
  -e "app_s3_bucket=artifacts-bucket" \
  -e "app_s3_key=myapp/myapp-1.0.0.tar.gz"
```

### Rolling Updates

```bash
# Update web servers one at a time
ansible-playbook playbooks/webservers.yml \
  -i inventories/prod/aws_ec2.yml \
  --forks 1
```

### Emergency Rollback

```bash
# Rollback to previous release
ansible-playbook playbooks/deploy.yml \
  -i inventories/dev/aws_ec2.yml \
  -e "app_rollback=true" \
  -e "app_rollback_version=previous"
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   ```bash
   # Test connectivity
   ansible all -i inventories/dev/aws_ec2.yml -m ping
   ```

2. **Vault Password Error**
   ```bash
   # Verify vault password file
   ansible-vault view group_vars/all/vault.yml --vault-password-file .vault_pass
   ```

3. **AWS Credentials Issue**
   ```bash
   # Test AWS credentials
   aws sts get-caller-identity
   ```

4. **Dynamic Inventory Empty**
   ```bash
   # Debug inventory
   ansible-inventory -i inventories/dev/aws_ec2.yml --list -vvv
   ```

## Contributing

1. Create a feature branch
2. Make changes
3. Run molecule tests
4. Submit pull request
5. Wait for CI/CD pipeline to pass
6. Request review

## License

MIT License - See LICENSE file for details.
