# Cleerly DevOps Engineer III — Interview Projects

Five production-grade AWS DevOps projects aligned to the Cleerly DevOps Engineer III job description.

## Projects Overview

| # | Project | Key Technologies |
|---|---------|-----------------|
| 01 | Production VPC + EKS with Terraform | Terraform, AWS EKS, VPC, S3, DynamoDB |
| 02 | GitHub Actions CI/CD + Security Scanning | GitHub Actions, ECR, Trivy, ArgoCD, Helm |
| 03 | EKS Autoscaling & Observability | Karpenter, Prometheus, Grafana, kube-prometheus-stack |
| 04 | HIPAA/HITRUST/SOC 2 Compliance Guardrails | AWS Config, GuardDuty, CloudTrail, Security Hub, IAM |
| 05 | SLO/SLA Monitoring & Incident Response | CloudWatch, PagerDuty, SSM Automation, Error Budgets |

## Prerequisites

```bash
# Install required tools
brew install terraform awscli kubectl helm
brew install kustomize argocd trivy tfsec checkov

# Configure AWS CLI
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: us-east-1
# Default output format: json

# Verify setup
aws sts get-caller-identity
terraform --version
kubectl version --client
helm version
```

## JD Alignment

- **IaC** → Project 01: Terraform modules, remote state, policy scanning
- **CI/CD Pipelines** → Project 02: GitHub Actions, ECR, GitOps with ArgoCD
- **EKS Management** → Project 03: Autoscaling, upgrades, observability
- **HIPAA/HITRUST/SOC 2** → Project 04: Continuous compliance automation
- **SLOs/Incident Response** → Project 05: Error budgets, runbooks, PIR dashboards

## Folder Structure

```
cleerly-devops-projects/
├── README.md
├── project-01-terraform-eks/
├── project-02-cicd-github-actions/
├── project-03-eks-observability/
├── project-04-hipaa-compliance/
└── project-05-slo-monitoring/
```
