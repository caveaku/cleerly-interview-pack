#!/usr/bin/env bash
# ============================================================
# Cleerly DevOps Engineer III — Master Setup Script
# Validates tooling and walks through all 5 project commands
# Usage: bash setup.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

REQUIRED_TOOLS=(terraform aws kubectl helm argocd trivy tfsec checkov)

echo ""
echo "============================================================"
echo "  Cleerly DevOps Interview Projects — Environment Check"
echo "============================================================"
echo ""

# ─────────────────────────────────────────────
# Check required tools
# ─────────────────────────────────────────────
info "Checking required tools..."
ALL_GOOD=true
for tool in "${REQUIRED_TOOLS[@]}"; do
  if command -v "$tool" &>/dev/null; then
    success "$tool is installed ($(command -v $tool))"
  else
    warn "$tool is NOT installed"
    ALL_GOOD=false
  fi
done

if [ "$ALL_GOOD" = false ]; then
  echo ""
  warn "Install missing tools:"
  echo "  brew install terraform awscli kubectl helm"
  echo "  brew install argocd trivy tfsec"
  echo "  pip install checkov --break-system-packages"
fi

# ─────────────────────────────────────────────
# Check AWS authentication
# ─────────────────────────────────────────────
echo ""
info "Checking AWS authentication..."
if aws sts get-caller-identity &>/dev/null; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  USER=$(aws sts get-caller-identity --query Arn --output text)
  success "Authenticated as: $USER"
  success "Account ID: $ACCOUNT"
  export AWS_ACCOUNT_ID=$ACCOUNT
else
  error "AWS not authenticated. Run: aws configure"
  exit 1
fi

# ─────────────────────────────────────────────
# Project menu
# ─────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Select a project to execute:"
echo "  [1] Project 01 — Terraform VPC + EKS"
echo "  [2] Project 02 — GitHub Actions CI/CD"
echo "  [3] Project 03 — EKS Autoscaling & Observability"
echo "  [4] Project 04 — HIPAA/SOC2 Compliance"
echo "  [5] Project 05 — SLO Monitoring & Incident Response"
echo "  [0] Validate all (dry-run checks only)"
echo "============================================================"
echo ""
read -p "Enter choice [0-5]: " CHOICE

case $CHOICE in
  1)
    echo ""
    info "=== Project 01: Terraform VPC + EKS ==="
    cd project-01-terraform-eks

    info "Initializing Terraform..."
    terraform fmt -recursive
    terraform validate
    success "Terraform config is valid"

    info "Running security scan with tfsec..."
    tfsec . --minimum-severity HIGH || warn "tfsec found issues — review before applying"

    info "Running checkov compliance scan..."
    checkov -d . --framework terraform --quiet \
      --check CKV_AWS_58,CKV_AWS_39,CKV_AWS_111 || warn "checkov found issues"

    info "Terraform plan (requires real AWS credentials):"
    echo "  terraform plan -var-file=envs/prod/terraform.tfvars"
    echo ""
    info "To apply:"
    echo "  terraform apply -var-file=envs/prod/terraform.tfvars"
    ;;

  2)
    echo ""
    info "=== Project 02: GitHub Actions CI/CD ==="
    info "Validating GitHub Actions workflow YAML..."
    if command -v actionlint &>/dev/null; then
      actionlint .github/workflows/ci-cd.yml
      success "Workflow YAML is valid"
    else
      warn "actionlint not installed. Install: brew install actionlint"
    fi

    info "Checking ECR repository exists..."
    if aws ecr describe-repositories --repository-names cleerly-api &>/dev/null; then
      success "ECR repo exists"
    else
      info "Creating ECR repository..."
      aws ecr create-repository \
        --repository-name cleerly-api \
        --image-scanning-configuration scanOnPush=true
      success "ECR repo created"
    fi

    info "Running Trivy scan on local filesystem..."
    trivy fs . --severity CRITICAL,HIGH --scanners secret,misconfig \
      --exit-code 0 || warn "Trivy found issues"
    ;;

  3)
    echo ""
    info "=== Project 03: EKS Autoscaling & Observability ==="
    export CLUSTER_NAME=${CLUSTER_NAME:-cleerly-prod}

    info "Checking EKS cluster access..."
    if aws eks describe-cluster --name $CLUSTER_NAME &>/dev/null; then
      aws eks update-kubeconfig --name $CLUSTER_NAME --region us-east-1
      success "kubectl configured for $CLUSTER_NAME"
      kubectl get nodes
    else
      warn "Cluster $CLUSTER_NAME not found. Run Project 01 first."
    fi

    info "Validating Karpenter manifest..."
    kubectl apply --dry-run=client -f project-03-eks-observability/karpenter/nodepool.yaml \
      || warn "Manifest validation failed"

    info "Validating Prometheus alert rules..."
    kubectl apply --dry-run=client \
      -f project-03-eks-observability/monitoring/alerts/prometheus-rules.yaml \
      || warn "Alert rules validation failed"
    ;;

  4)
    echo ""
    info "=== Project 04: HIPAA/SOC2 Compliance ==="

    info "Checking Security Hub status..."
    aws securityhub describe-hub --region us-east-1 2>/dev/null \
      && success "Security Hub is enabled" \
      || warn "Security Hub not enabled. Run enablement commands in README."

    info "Checking GuardDuty status..."
    DETECTOR=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null)
    if [ -n "$DETECTOR" ] && [ "$DETECTOR" != "None" ]; then
      success "GuardDuty enabled. Detector: $DETECTOR"
    else
      warn "GuardDuty not enabled. Run enablement commands in README."
    fi

    info "Validating IAM boundary policy JSON..."
    aws iam validate-policy \
      --policy-document file://project-04-hipaa-compliance/iam/devops-boundary.json \
      --policy-type RESOURCE_POLICY 2>/dev/null \
      && success "IAM policy JSON is valid" \
      || warn "IAM policy validation requires specific permissions"

    info "Checking Config recorder status..."
    aws configservice describe-configuration-recorder-status \
      --query "ConfigurationRecordersStatus[0].{Name:name,Recording:recording}" \
      --output table 2>/dev/null || warn "AWS Config not enabled"
    ;;

  5)
    echo ""
    info "=== Project 05: SLO Monitoring & Incident Response ==="

    info "Validating SLO definitions YAML..."
    kubectl apply --dry-run=client \
      -f project-05-slo-monitoring/slo-definitions/cleerly-slos.yaml \
      || warn "SLO YAML validation failed (cluster access required)"

    info "Checking CloudWatch alarms..."
    aws cloudwatch describe-alarms \
      --alarm-name-prefix "cleerly-" \
      --query "MetricAlarms[*].{Alarm:AlarmName,State:StateValue}" \
      --output table 2>/dev/null || warn "No Cleerly CloudWatch alarms found yet"

    info "Checking SSM documents..."
    aws ssm list-documents \
      --filters Key=Name,Values=Cleerly \
      --query "DocumentIdentifiers[*].{Name:Name,Version:DocumentVersion}" \
      --output table 2>/dev/null || warn "No Cleerly SSM documents found yet"
    ;;

  0)
    echo ""
    info "=== Full Validation (Dry Run) ==="

    info "Terraform format check..."
    terraform fmt -check -recursive project-01-terraform-eks/ \
      && success "Terraform files are formatted" \
      || warn "Run: terraform fmt -recursive"

    info "Kubernetes manifest validation..."
    for manifest in \
      project-03-eks-observability/karpenter/nodepool.yaml \
      project-03-eks-observability/monitoring/alerts/prometheus-rules.yaml \
      project-05-slo-monitoring/slo-definitions/cleerly-slos.yaml; do
      kubectl apply --dry-run=client -f $manifest 2>/dev/null \
        && success "$manifest is valid" \
        || warn "$manifest validation failed (cluster access needed)"
    done

    info "AWS connectivity check..."
    aws sts get-caller-identity --output table
    success "All dry-run checks complete"
    ;;

  *)
    error "Invalid choice: $CHOICE"
    exit 1
    ;;
esac

echo ""
echo "============================================================"
success "Done! Review the README.md in each project folder for"
echo "       full command reference and interview talking points."
echo "============================================================"
echo ""
