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

---

## Interview Talking Points

### Project 01 — Production VPC + EKS with Terraform

> "I built a production-grade AWS environment from scratch using Terraform modules with remote state stored in S3 and DynamoDB for state locking. I provisioned a multi-AZ VPC with private subnets for EKS workloads, a private-only API endpoint to satisfy HIPAA requirements, KMS-encrypted secrets, and full control plane logging to CloudWatch. I also enforced security policy scanning with `tfsec` and `checkov` as pre-commit hooks so infrastructure issues are caught before they ever reach a PR. This directly maps to your expectation of owning and maintaining a Terraform codebase with IaC best practices."

---

### Project 02 — GitHub Actions CI/CD + Security Scanning

> "I designed an end-to-end CI/CD pipeline using GitHub Actions that builds Docker images, pushes them to ECR using OIDC — no long-lived AWS keys — runs Trivy container scanning to block on CRITICAL and HIGH CVEs, and deploys to EKS via ArgoCD GitOps. Every deployment is tied to a Git SHA, fully auditable, and self-healing. This directly addresses your requirement for building and maintaining secure build pipelines using GitHub Actions."

---

### Project 03 — EKS Autoscaling & Observability

> "I deployed Karpenter for node autoscaling — which provisions nodes in under 60 seconds and consolidates underutilized ones automatically — and stood up the full kube-prometheus-stack with custom SLO recording rules and alerting. I also documented the zero-downtime EKS upgrade process, including deprecated API detection with Pluto. This covers your requirement to manage EKS environments including scaling, upgrades, and observability."

---

### Project 04 — HIPAA/HITRUST/SOC 2 Compliance Guardrails

> "I automated continuous compliance using AWS Security Hub with the HIPAA standard enabled, GuardDuty with EKS runtime monitoring, Config rules for drift detection, and CloudTrail with S3 Object Lock in COMPLIANCE mode for tamper-proof 6-year log retention. I also implemented IAM permission boundaries to prevent privilege escalation and an EventBridge + Lambda auto-remediation loop to enforce boundaries on every new role. This maps directly to your need to ensure alignment with HIPAA, HITRUST, and SOC 2 in a healthcare environment."

---

### Project 05 — SLO/SLA Monitoring & Incident Response

> "I defined SLOs as code using Sloth — including a 99.9% availability SLO and a 30-second CT scan latency SLO — with multi-window burn rate alerts to catch both fast and slow budget drains. I reduced alert fatigue using CloudWatch composite alarms that require correlated signals before paging. I also built SSM Automation runbooks for codified, auditable incident response and a CloudWatch PIR dashboard with annotated incident timelines. This directly supports your requirement to define and track SLOs, participate in on-call, and lead post-incident reviews."

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
