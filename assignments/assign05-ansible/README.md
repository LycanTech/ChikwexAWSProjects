# Chikwex Infrastructure

Infrastructure Automation with Ansible for AWS - Complete infrastructure-as-code solution for deploying and managing web servers, database servers, and applications on AWS.

## Features

- **Dynamic AWS Inventory** - Automatic EC2 instance discovery using tags
- **Role-Based Configuration** - Modular, reusable Ansible roles
- **Security Hardening** - Firewall, fail2ban, SELinux, auditd
- **AWS Integration** - SSM, CloudWatch, Secrets Manager
- **Zero-Downtime Deployments** - Rolling updates with health checks
- **CI/CD Pipeline** - GitHub Actions for automated testing and deployment
- **Molecule Testing** - Automated role testing with Docker

## Project Structure

```
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # Ansible Galaxy dependencies
├── inventories/
│   ├── dev/                 # Development environment
│   │   ├── aws_ec2.yml      # AWS dynamic inventory
│   │   └── hosts.yml        # Static fallback
│   └── prod/                # Production environment
├── group_vars/
│   ├── all/                 # Global variables + vault
│   ├── webservers/          # Web server config
│   └── dbservers/           # Database config
├── playbooks/
│   ├── site.yml             # Master playbook
│   ├── webservers.yml       # Web servers only
│   ├── dbservers.yml        # Database servers only
│   └── deploy.yml           # Application deployment
├── roles/
│   ├── common/              # Base system configuration
│   ├── nginx/               # Nginx web server
│   ├── postgresql/          # PostgreSQL database
│   ├── security/            # Security hardening
│   ├── aws_integration/     # AWS services (SSM, CloudWatch)
│   └── app_deploy/          # Application deployment
├── molecule/                # Molecule tests
└── .github/workflows/       # CI/CD pipeline
```

---

## Step-by-Step AWS Deployment Guide

### Prerequisites

Before you begin, ensure you have:

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI v2 installed
- [ ] Python 3.9+ installed
- [ ] Ansible 2.14+ installed
- [ ] SSH key pair for EC2 instances

---

### Step 1: Install Dependencies

```bash
# Install Python packages
pip install ansible boto3 botocore ansible-lint

# Install Ansible Galaxy collections
ansible-galaxy collection install -r requirements.yml
```

**Verify installation:**
```bash
ansible --version
aws --version
python --version
```

---

### Step 2: Configure AWS Credentials

**Option A: Environment Variables**
```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"
```

**Option B: AWS Credentials File**
```bash
# Create/edit ~/.aws/credentials
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# Create/edit ~/.aws/config
[default]
region = us-east-1
output = json
```

**Verify credentials:**
```bash
aws sts get-caller-identity
```

---

### Step 3: Create EC2 Key Pair

```bash
# Create a new key pair
aws ec2 create-key-pair \
  --key-name chikwex-infra-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/chikwex-infra-key.pem

# Set proper permissions
chmod 400 ~/.ssh/chikwex-infra-key.pem
```

---

### Step 4: Launch EC2 Instances

Launch instances with the required tags for dynamic inventory:

```bash
# Launch a web server instance
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.micro \
  --key-name chikwex-infra-key \
  --security-group-ids sg-xxxxxxxx \
  --subnet-id subnet-xxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[
    {Key=Name,Value=web-dev-01},
    {Key=Environment,Value=dev},
    {Key=Project,Value=chikwex-infra},
    {Key=Role,Value=webserver}
  ]' \
  --count 1

# Launch a database server instance
aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --instance-type t3.small \
  --key-name chikwex-infra-key \
  --security-group-ids sg-xxxxxxxx \
  --subnet-id subnet-xxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[
    {Key=Name,Value=db-dev-01},
    {Key=Environment,Value=dev},
    {Key=Project,Value=chikwex-infra},
    {Key=Role,Value=database}
  ]' \
  --count 1
```

**Required Tags for Dynamic Inventory:**
| Tag | Value | Purpose |
|-----|-------|---------|
| `Environment` | `dev` or `prod` | Environment filtering |
| `Project` | `chikwex-infra` | Project filtering |
| `Role` | `webserver`, `database`, `application` | Role-based grouping |

---

### Step 5: Configure Security Groups

Ensure your security groups allow:

**Web Servers (webservers):**
- SSH (22) - from your IP or bastion
- HTTP (80) - from anywhere or ALB
- HTTPS (443) - from anywhere or ALB

**Database Servers (dbservers):**
- SSH (22) - from your IP or bastion
- PostgreSQL (5432) - from VPC CIDR only

```bash
# Example: Create security group for web servers
aws ec2 create-security-group \
  --group-name chikwex-web-sg \
  --description "Security group for web servers" \
  --vpc-id vpc-xxxxxxxx

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp --port 22 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
```

---

### Step 6: Set Up Ansible Vault

Create a vault password file:
```bash
# Create vault password file (use a strong password)
echo "YourSecureVaultPassword123!" > .vault_pass
chmod 600 .vault_pass
```

Edit the vault file with your secrets:
```bash
# Edit vault with your actual credentials
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

**Update these values in vault.yml:**
```yaml
vault_aws_account_id: "123456789012"  # Your AWS account ID
vault_postgresql_admin_password: "YourSecureDBPassword!"
vault_admin_ssh_public_key: "ssh-rsa AAAAB3... your-key"
```

---

### Step 7: Verify Dynamic Inventory

Test that Ansible can discover your EC2 instances:

```bash
# List all discovered hosts
ansible-inventory -i inventories/dev/aws_ec2.yml --list

# Show inventory graph
ansible-inventory -i inventories/dev/aws_ec2.yml --graph

# Test connectivity to all hosts
ansible all -i inventories/dev/aws_ec2.yml -m ping
```

**Expected output:**
```
@all:
  |--@webservers:
  |  |--web-dev-01
  |--@dbservers:
  |  |--db-dev-01
```

---

### Step 8: Run Playbook (Dry Run)

Always run a dry run first to see what changes will be made:

```bash
ansible-playbook playbooks/site.yml \
  -i inventories/dev/aws_ec2.yml \
  --vault-password-file .vault_pass \
  --check \
  --diff
```

**Review the output** - it shows what would change without making actual changes.

---

### Step 9: Deploy Infrastructure

Run the full deployment:

```bash
# Deploy everything
ansible-playbook playbooks/site.yml \
  -i inventories/dev/aws_ec2.yml \
  --vault-password-file .vault_pass

# Or deploy specific components:

# Web servers only
ansible-playbook playbooks/webservers.yml \
  -i inventories/dev/aws_ec2.yml \
  --vault-password-file .vault_pass

# Database servers only
ansible-playbook playbooks/dbservers.yml \
  -i inventories/dev/aws_ec2.yml \
  --vault-password-file .vault_pass
```

---

### Step 10: Verify Deployment

**Check web server:**
```bash
# SSH into web server
ssh -i ~/.ssh/chikwex-infra-key.pem ec2-user@<web-server-ip>

# Verify nginx is running
sudo systemctl status nginx
curl http://localhost/health
```

**Check database server:**
```bash
# SSH into database server
ssh -i ~/.ssh/chikwex-infra-key.pem ec2-user@<db-server-ip>

# Verify PostgreSQL is running
sudo systemctl status postgresql-15
sudo -u postgres psql -c "SELECT version();"
```

---

### Step 11: Deploy Application (Optional)

To deploy an application:

```bash
ansible-playbook playbooks/deploy.yml \
  -i inventories/dev/aws_ec2.yml \
  --vault-password-file .vault_pass \
  -e "app_name=myapp" \
  -e "app_git_repo=https://github.com/your-org/your-app.git" \
  -e "app_git_branch=main"
```

---

## Common Commands Reference

```bash
# Run with specific tags
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml --tags "nginx"

# Skip specific tags
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml --skip-tags "postgresql"

# Limit to specific hosts
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml --limit "webservers"

# Increase verbosity for debugging
ansible-playbook playbooks/site.yml -i inventories/dev/aws_ec2.yml -vvv

# Run ad-hoc commands
ansible webservers -i inventories/dev/aws_ec2.yml -m shell -a "nginx -t"
ansible dbservers -i inventories/dev/aws_ec2.yml -m shell -a "systemctl status postgresql-15"
```

---

## Production Deployment

For production, use the production inventory:

```bash
# Dry run first!
ansible-playbook playbooks/site.yml \
  -i inventories/prod/aws_ec2.yml \
  --vault-password-file .vault_pass \
  --check --diff

# Then deploy
ansible-playbook playbooks/site.yml \
  -i inventories/prod/aws_ec2.yml \
  --vault-password-file .vault_pass
```

---

## Troubleshooting

### SSH Connection Issues

```bash
# Test SSH manually
ssh -i ~/.ssh/chikwex-infra-key.pem -o StrictHostKeyChecking=no ec2-user@<ip>

# Check if host key checking is disabled in ansible.cfg
grep host_key_checking ansible.cfg
```

### Dynamic Inventory Empty

```bash
# Debug inventory with verbose output
ansible-inventory -i inventories/dev/aws_ec2.yml --list -vvv

# Check AWS credentials
aws sts get-caller-identity

# Verify instances have correct tags
aws ec2 describe-instances --filters "Name=tag:Project,Values=chikwex-infra"
```

### Vault Password Issues

```bash
# Test vault decryption
ansible-vault view group_vars/all/vault.yml --vault-password-file .vault_pass

# Re-encrypt with new password
ansible-vault rekey group_vars/all/vault.yml
```

---

## CI/CD with GitHub Actions

The project includes a GitHub Actions workflow that:
1. Lints Ansible code
2. Runs Molecule tests
3. Scans for secrets
4. Deploys to dev automatically
5. Deploys to prod with manual approval

**Required GitHub Secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `ANSIBLE_VAULT_PASSWORD`

---

## Documentation

- [Detailed Documentation](docs/README.md)
- [Execution Report](docs/EXECUTION_REPORT.md)

## License

MIT License
