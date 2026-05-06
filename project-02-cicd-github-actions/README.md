# Project 02 — GitHub Actions CI/CD Pipeline with Container Security Scanning

## Objective
End-to-end build, scan, and deploy pipeline using GitHub Actions, Amazon ECR, Trivy, and ArgoCD.
Every commit is built, vulnerability-scanned, and GitOps-deployed to EKS with a full audit trail.

## JD Alignment
> "Design, implement, and maintain build pipelines using GitHub Actions"
> "Ensure scalability, performance, and security of our infrastructure"

---

## Step 1 — Create ECR Repository & OIDC Trust for GitHub

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name cleerly-api \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  --region us-east-1

# Enable ECR lifecycle policy (keep last 30 images)
aws ecr put-lifecycle-policy \
  --repository-name cleerly-api \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "description": "Keep last 30 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 30
      },
      "action": { "type": "expire" }
    }]
  }'

# Set up OIDC provider for GitHub Actions (no long-lived keys)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create IAM role for GitHub Actions
cat > github-actions-trust.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/cleerly-api:*"
      }
    }
  }]
}
EOF

aws iam create-role \
  --role-name GitHubActionsRole \
  --assume-role-policy-document file://github-actions-trust.json

aws iam attach-role-policy \
  --role-name GitHubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

---

## Step 2 — GitHub Actions Workflow (Build + Push to ECR)

```yaml
# .github/workflows/ci-cd.yml
# This file is committed to your repo at .github/workflows/ci-cd.yml

name: Build → Scan → Deploy

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  AWS_REGION:    us-east-1
  ECR_REGISTRY:  123456789012.dkr.ecr.us-east-1.amazonaws.com
  IMAGE_NAME:    cleerly-api

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.build.outputs.image-tag }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag, and push Docker image
        id: build
        run: |
          IMAGE_TAG=${{ github.sha }}
          docker build \
            --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
            --build-arg GIT_COMMIT=$IMAGE_TAG \
            -t $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG \
            -t $ECR_REGISTRY/$IMAGE_NAME:latest \
            .
          docker push $ECR_REGISTRY/$IMAGE_NAME:$IMAGE_TAG
          docker push $ECR_REGISTRY/$IMAGE_NAME:latest
          echo "image-tag=$IMAGE_TAG" >> $GITHUB_OUTPUT
```

---

## Step 3 — Container Security Scanning with Trivy

```yaml
# Add to .github/workflows/ci-cd.yml (continued)

  security-scan:
    needs: build
    runs-on: ubuntu-latest
    permissions:
      security-events: write   # needed to upload SARIF to GitHub Security tab

    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: us-east-1

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.ECR_REGISTRY }}/${{ env.IMAGE_NAME }}:${{ needs.build.outputs.image-tag }}
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL,HIGH
          exit-code: '1'          # Block deploy on any CRITICAL or HIGH CVE
          ignore-unfixed: true

      - name: Upload Trivy results to GitHub Security tab
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: trivy-results.sarif

      - name: Run Trivy on filesystem (catch secrets/misconfigs)
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          scan-ref: .
          format: table
          severity: CRITICAL,HIGH
          scanners: secret,misconfig
```

---

## Step 4 — GitOps Deployment with ArgoCD

```bash
# Install ArgoCD on EKS
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available \
  deployment/argocd-server -n argocd --timeout=120s

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access ArgoCD UI (for demo)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Create ArgoCD application pointing to your Git repo
cat << 'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cleerly-api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_ORG/cleerly-api
    targetRevision: main
    path: k8s/helm/cleerly-api
    helm:
      valueFiles:
        - values-prod.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

```yaml
# Add deploy step to .github/workflows/ci-cd.yml (continued)

  deploy:
    needs: [build, security-scan]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.GH_TOKEN }}

      - name: Update Helm values with new image tag
        run: |
          cd k8s/helm/cleerly-api
          sed -i "s/tag:.*/tag: ${{ needs.build.outputs.image-tag }}/" values-prod.yaml
          git config user.email "ci@cleerlyhealth.com"
          git config user.name "GitHub Actions"
          git add values-prod.yaml
          git commit -m "chore(deploy): update image to ${{ needs.build.outputs.image-tag }}"
          git push

      - name: Wait for ArgoCD sync
        run: |
          argocd app wait cleerly-api \
            --sync \
            --health \
            --timeout 300 \
            --server argocd.internal.cleerly.com
```

---

## Interview Talking Points

**"Why OIDC for GitHub Actions instead of storing an AWS access key as a secret?"**
Long-lived static credentials are the number-one cause of cloud breaches. OIDC issues short-lived tokens scoped to a specific repo and branch — they expire after the job ends and can't be leaked, rotated incorrectly, or reused outside their context. It also eliminates the ops burden of rotating secrets across dozens of repos.

**"What happens if Trivy finds a CRITICAL vulnerability?"**
The pipeline exits with code 1, blocking the deploy job from running. The SARIF results are still uploaded to the GitHub Security tab so the developer sees exactly which CVE, which package, and what the fix version is — all without leaving GitHub. The `ignore-unfixed: true` flag avoids blocking on CVEs where no upstream fix exists yet, so the team isn't held hostage by third-party package timelines.

**"Why GitOps with ArgoCD instead of kubectl apply in the pipeline?"**
Direct `kubectl apply` in CI is imperative and stateless — if the cluster drifts, nothing catches it. ArgoCD continuously reconciles desired state (Git) with actual state (cluster). `selfHeal: true` auto-reverts manual changes, and `prune: true` removes resources deleted from Git. Every deployment is traceable to a Git commit, which satisfies the audit requirements in a HIPAA environment.

**"How do you handle a rollback?"**
Two options: revert the Helm values commit in Git (ArgoCD auto-syncs within seconds), or use `argocd app rollback cleerly-api <revision>` to jump to a previous sync. Because image tags are Git SHAs, I always know exactly what code is running and can reproduce any historical deployment deterministically.

**"What's the image tagging strategy and why?"**
Images are tagged with the full Git SHA. This is immutable — you can never accidentally overwrite a deployed image, and you can trace any running container back to the exact commit and PR that produced it. `latest` is also pushed for convenience in dev but is never referenced in production Helm values.

**"How would you handle secrets in the pipeline without hardcoding them?"**
AWS Secrets Manager + the External Secrets Operator in Kubernetes. The pipeline itself never touches secrets — it only pushes an image tag to Git. The running pod fetches secrets at startup from Secrets Manager via a synced `ExternalSecret` CRD, with KMS encryption at rest and IAM role-based access scoped to the specific namespace.

## Step 5 — Validation Commands

```bash
# Verify image was pushed to ECR
aws ecr list-images \
  --repository-name cleerly-api \
  --query "imageIds[*].{Tag:imageTag,Digest:imageDigest}" \
  --output table

# Check ECR scan results
aws ecr describe-image-scan-findings \
  --repository-name cleerly-api \
  --image-id imageTag=latest \
  --query "imageScanFindings.findingSeverityCounts"

# Watch ArgoCD sync status
argocd app get cleerly-api
argocd app sync cleerly-api --watch

# Verify rollout in EKS
kubectl rollout status deployment/cleerly-api -n production
kubectl get pods -n production -l app=cleerly-api
kubectl describe pod -n production -l app=cleerly-api | grep Image:

# Watch Argo Rollouts canary (if configured)
kubectl argo rollouts get rollout cleerly-api -n production --watch
```
