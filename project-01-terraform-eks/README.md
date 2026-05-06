# Project 01 — Production VPC + EKS Cluster with Terraform

## Objective
Build a multi-AZ, production-grade AWS environment from scratch using Terraform modules.
Demonstrates: IaC best practices, remote state, EKS provisioning, and security scanning.

## JD Alignment
> "Own and maintain the Terraform codebase, implementing infrastructure as code best practices"
> "Manage Kubernetes environments (EKS), including cluster provisioning"

---

## Step 1 — Initialize Terraform Project & Remote State Backend

```bash
# Create folder structure
mkdir -p cleerly-infra/{modules/{vpc,eks,security},envs/{dev,prod}}
cd cleerly-infra

# Initialize Terraform
terraform init

# Create S3 bucket for remote state
aws s3api create-bucket \
  --bucket cleerly-tf-state \
  --region us-east-1

# Enable versioning on state bucket
aws s3api put-bucket-versioning \
  --bucket cleerly-tf-state \
  --versioning-configuration Status=Enabled

# Enable encryption on state bucket
aws s3api put-bucket-encryption \
  --bucket cleerly-tf-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms"
      }
    }]
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name cleerly-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

---

## Step 2 — Provision Multi-AZ VPC

```bash
# modules/vpc/main.tf
cat > modules/vpc/main.tf << 'EOF'
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "cleerly-prod-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["us-east-1a", "us-east-1b", "us-east-1c"]

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = false   # One NAT per AZ for HA
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # Required tags for EKS to discover subnets
  private_subnet_tags = {
    "kubernetes.io/cluster/cleerly-prod" = "shared"
    "kubernetes.io/role/internal-elb"    = "1"
  }
  public_subnet_tags = {
    "kubernetes.io/cluster/cleerly-prod" = "shared"
    "kubernetes.io/role/elb"             = "1"
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    HIPAA       = "true"
    Project     = "cleerly"
  }
}
EOF

# Plan and apply VPC
terraform plan -var-file=envs/prod/terraform.tfvars -target=module.vpc
terraform apply -var-file=envs/prod/terraform.tfvars -target=module.vpc -auto-approve

# Verify subnets
aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=cleerly" \
  --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Public:MapPublicIpOnLaunch}" \
  --output table
```

---

## Step 3 — Deploy EKS Cluster with Managed Node Groups

```bash
# modules/eks/main.tf
cat > modules/eks/main.tf << 'EOF'
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"

  cluster_name    = "cleerly-prod"
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # HIPAA: Private endpoint only — no public API server access
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false

  # Encrypt secrets with KMS
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  # Enable EKS control plane logging
  cluster_enabled_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ]

  eks_managed_node_groups = {
    general = {
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      instance_types = ["m5.xlarge"]
      capacity_type  = "ON_DEMAND"

      # Encrypt EBS volumes for HIPAA
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      labels = {
        Environment = "prod"
        NodeGroup   = "general"
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"         = "true"
        "k8s.io/cluster-autoscaler/cleerly-prod"    = "owned"
      }
    }

    gpu = {
      min_size       = 0
      max_size       = 4
      desired_size   = 0
      instance_types = ["g4dn.xlarge"]
      capacity_type  = "SPOT"   # Cost optimization for AI workloads

      labels = {
        NodeGroup = "gpu"
        workload  = "ai-inference"
      }

      taints = [{
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    HIPAA       = "true"
  }
}
EOF

terraform plan -var-file=envs/prod/terraform.tfvars
terraform apply -var-file=envs/prod/terraform.tfvars -auto-approve

# Configure kubectl
aws eks update-kubeconfig --name cleerly-prod --region us-east-1

# Verify cluster
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

---

## Step 4 — Enforce Security Policies with tfsec & checkov

```bash
# Install security scanning tools
brew install tfsec
pip install checkov --break-system-packages

# Run tfsec static analysis
tfsec . --format json > security-report.json
tfsec . --format lovely

# Run checkov for compliance checks
# CKV_AWS_58  = EKS secrets encryption enabled
# CKV_AWS_39  = S3 MFA delete enabled
# CKV_AWS_111 = IAM no wildcard permissions
# CKV_AWS_79  = EC2 metadata service v2 (IMDSv2) required
checkov -d . \
  --framework terraform \
  --check CKV_AWS_58,CKV_AWS_39,CKV_AWS_111,CKV_AWS_79 \
  --output cli \
  --output json \
  --output-file-path ./reports/

# Add pre-commit hooks for automated scanning on every commit
cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.92.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tfsec
      - id: terraform_checkov
        args:
          - --args=--check CKV_AWS_58,CKV_AWS_39,CKV_AWS_111
EOF

pre-commit install
pre-commit run --all-files
```

---

## Interview Talking Points

**"Why S3 + DynamoDB for remote state instead of Terraform Cloud?"**
S3 gives you full control over encryption (KMS), versioning, and access policies — critical in a HIPAA environment where you own the audit trail. DynamoDB locking costs near zero and prevents concurrent applies from corrupting state. Terraform Cloud is a valid alternative but adds a third-party dependency to a sensitive data plane.

**"Why is the EKS API endpoint set to private-only?"**
HIPAA requires that systems processing PHI not be exposed to the public internet unless absolutely necessary. A private-only endpoint means the Kubernetes API is only reachable from within the VPC — eliminating an entire class of credential-stuffing and brute-force attack surface. Engineers access it over a VPN or bastion.

**"Why a separate NAT gateway per AZ instead of a single shared one?"**
A single NAT gateway is a regional single point of failure. If the AZ hosting it goes down, all private subnet egress traffic across the cluster drops. The extra cost (~$32/month per AZ) is the price of availability in a production healthcare environment where downtime has patient impact.

**"How do you prevent insecure Terraform from reaching production?"**
Shift-left: `tfsec` and `checkov` run as pre-commit hooks on every commit and again in CI. Specific checks like `CKV_AWS_58` (EKS secrets encryption), `CKV_AWS_79` (IMDSv2), and `CKV_AWS_111` (no wildcard IAM) are enforced as hard gates — the pipeline fails if any are violated. This means security issues are caught at the developer's keyboard, not in a prod deploy.

**"Why does the GPU node group use SPOT capacity?"**
AI inference workloads at Cleerly are batch-oriented and fault-tolerant — a preempted node just re-queues the scan job. SPOT instances on `g4dn.xlarge` run 60–70% cheaper than On-Demand. The taint `nvidia.com/gpu=true:NoSchedule` ensures only GPU-aware workloads land on these nodes, preventing accidental scheduling of general services onto expensive hardware.

**"Walk me through how you'd recover from a corrupted Terraform state."**
S3 versioning means every state file version is retained. I'd first run `terraform state list` to understand current state, then restore the previous S3 version, unlock the DynamoDB entry manually if needed, and run `terraform plan` to diff actual infrastructure against the restored state before touching anything.

## Validation Commands

```bash
# Confirm EKS cluster is healthy
aws eks describe-cluster \
  --name cleerly-prod \
  --query "cluster.{Status:status,Version:version,Endpoint:endpoint}" \
  --output table

# Confirm private endpoint only (public access = false)
aws eks describe-cluster \
  --name cleerly-prod \
  --query "cluster.resourcesVpcConfig.endpointPublicAccess"

# Check EKS control plane logs in CloudWatch
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/eks/cleerly-prod" \
  --query "logGroups[*].logGroupName"

# Check all nodes Ready
kubectl get nodes --watch

# Check terraform state
terraform state list
terraform output
```
