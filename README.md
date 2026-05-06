# Cleerly DevOps Engineer III — Interview Projects

Five production-grade AWS DevOps projects aligned to the Cleerly DevOps Engineer III job description.

---

## Project Overview

| # | Project | Key Technologies |
|---|---------|-----------------|
| [01](./project-01-terraform-eks/) | Production VPC + EKS with Terraform | Terraform, AWS EKS, VPC, S3, DynamoDB |
| [02](./project-02-cicd-github-actions/) | GitHub Actions CI/CD + Security Scanning | GitHub Actions, ECR, Trivy, ArgoCD, Helm |
| [03](./project-03-eks-observability/) | EKS Autoscaling & Observability | Karpenter, Prometheus, Grafana, kube-prometheus-stack |
| [04](./project-04-hipaa-compliance/) | HIPAA/HITRUST/SOC 2 Compliance Guardrails | AWS Config, GuardDuty, CloudTrail, Security Hub, IAM |
| [05](./project-05-slo-monitoring/) | SLO/SLA Monitoring & Incident Response | CloudWatch, PagerDuty, SSM Automation, Error Budgets |

---

## Repository Structure

```
cleerly-interview-pack/
├── README.md
├── setup.sh
├── project-01-terraform-eks/
│   ├── README.md
│   ├── backend.tf
│   ├── eks-main.tf
│   ├── vpc-main.tf
│   └── terraform.tfvars
├── project-02-cicd-github-actions/
│   ├── README.md
│   ├── ci-cd.yml
│   └── helm-values-prod.yaml
├── project-03-eks-observability/
│   ├── README.md
│   ├── karpenter-nodepool.yaml
│   └── prometheus-rules.yaml
├── project-04-hipaa-compliance/
│   ├── README.md
│   ├── config-rules.tf
│   └── devops-boundary.json
└── project-05-slo-monitoring/
    ├── README.md
    ├── cleerly-slos.yaml
    └── runbook-restart-pods.json
```

---

## Project Details

### Project 01 — Production VPC + EKS with Terraform
Builds a multi-AZ, production-grade AWS environment using Terraform modules with remote state (S3 + DynamoDB locking), a hardened VPC, and a managed EKS cluster. Includes security scanning with `tfsec` and `checkov`.

**Files:** `backend.tf`, `vpc-main.tf`, `eks-main.tf`, `terraform.tfvars`

---

### Project 02 — GitHub Actions CI/CD + Security Scanning
End-to-end CI/CD pipeline using GitHub Actions: builds and pushes Docker images to ECR, runs Trivy container scanning, and deploys to EKS via ArgoCD GitOps with Helm.

**Files:** `ci-cd.yml`, `helm-values-prod.yaml`

---

### Project 03 — EKS Autoscaling & Observability
Configures Karpenter for node autoscaling and deploys the `kube-prometheus-stack` for cluster-wide observability. Includes custom Prometheus alerting rules and Grafana dashboards.

**Files:** `karpenter-nodepool.yaml`, `prometheus-rules.yaml`

---

### Project 04 — HIPAA/HITRUST/SOC 2 Compliance Guardrails
Implements continuous compliance automation using AWS Config rules, GuardDuty, CloudTrail, and Security Hub. Includes a least-privilege IAM permissions boundary for the DevOps team.

**Files:** `config-rules.tf`, `devops-boundary.json`

---

### Project 05 — SLO/SLA Monitoring & Incident Response
Defines SLOs and error budgets with CloudWatch, integrates PagerDuty alerting, and provides SSM Automation runbooks for incident response. Includes a post-incident review (PIR) dashboard.

**Files:** `cleerly-slos.yaml`, `runbook-restart-pods.json`

---

## Prerequisites

```bash
# Install required tools
brew install terraform awscli kubectl helm
brew install kustomize argocd trivy tfsec checkov

# Configure AWS CLI
aws configure

# Verify setup
aws sts get-caller-identity
terraform --version
kubectl version --client
helm version
```

---

## JD Alignment

| Job Description Requirement | Project |
|-----------------------------|---------|
| Own and maintain Terraform codebase, IaC best practices | Project 01 |
| CI/CD pipelines, container image security scanning | Project 02 |
| Manage EKS clusters, autoscaling, cluster upgrades | Project 03 |
| HIPAA, HITRUST, SOC 2 compliance automation | Project 04 |
| SLO/SLA monitoring, incident response, runbooks | Project 05 |
