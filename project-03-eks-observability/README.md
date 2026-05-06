# Project 03 — EKS Autoscaling & Full Observability Stack

## Objective
Deploy Karpenter for intelligent node autoscaling and a Prometheus + Grafana observability stack.
Demonstrates cluster lifecycle management, monitoring, and zero-downtime cluster upgrades.

## JD Alignment
> "Manage Kubernetes environments (EKS), including cluster provisioning, workload orchestration, scaling, upgrades, and observability"

---

## Step 1 — Install Karpenter for Node Autoscaling

```bash
# Set environment variables
export CLUSTER_NAME=cleerly-prod
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export KARPENTER_VERSION=v0.37.0

# Create Karpenter IAM role
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace karpenter \
  --name karpenter \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/KarpenterControllerPolicy \
  --approve \
  --override-existing-serviceaccounts

# Create EC2 node instance profile
aws iam create-instance-profile \
  --instance-profile-name KarpenterNodeInstanceProfile-$CLUSTER_NAME

aws iam add-role-to-instance-profile \
  --instance-profile-name KarpenterNodeInstanceProfile-$CLUSTER_NAME \
  --role-name KarpenterNodeRole-$CLUSTER_NAME

# Install Karpenter via Helm
helm repo add karpenter https://charts.karpenter.sh
helm repo update

helm install karpenter karpenter/karpenter \
  --namespace karpenter --create-namespace \
  --version $KARPENTER_VERSION \
  --set settings.aws.clusterName=$CLUSTER_NAME \
  --set settings.aws.clusterEndpoint=$(aws eks describe-cluster \
      --name $CLUSTER_NAME \
      --query "cluster.endpoint" \
      --output text) \
  --set settings.aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-$CLUSTER_NAME \
  --set settings.aws.interruptionQueueName=$CLUSTER_NAME

# Verify Karpenter running
kubectl get pods -n karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller
```

---

## Step 2 — Create Karpenter NodePool & EC2NodeClass

```bash
# Apply NodePool configuration
cat << 'EOF' | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        managed-by: karpenter
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["4"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
      kubelet:
        maxPods: 110
  limits:
    cpu: "200"
    memory: 400Gi
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
    expireAfter: 720h   # Rotate nodes every 30 days
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: KarpenterNodeRole-cleerly-prod
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: cleerly-prod
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: cleerly-prod
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        encrypted: true
EOF

# Test autoscaling by deploying a workload
kubectl create deployment inflate \
  --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7 \
  --replicas=0

kubectl scale deployment inflate --replicas=10
kubectl get nodes --watch   # Watch Karpenter provision new nodes in ~30s
kubectl scale deployment inflate --replicas=0
```

---

## Step 3 — Deploy kube-prometheus-stack (Prometheus + Grafana + Alertmanager)

```bash
# Add Prometheus community Helm repo
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring

# Create secret for Grafana admin password
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=$(openssl rand -base64 24) \
  -n monitoring

# Install kube-prometheus-stack
helm install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 61.0.0 \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.retentionSize=40GB \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=gp3 \
  --set grafana.admin.existingSecret=grafana-admin-secret \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=10Gi

# Verify all pods running
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Access Grafana UI (development only — use ingress in prod)
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
# Open http://localhost:3000  (admin / <password from secret>)
```

---

## Step 4 — Configure ServiceMonitor & Custom SLO Recording Rules

```bash
# ServiceMonitor: tells Prometheus to scrape your app
cat << 'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cleerly-api
  namespace: production
  labels:
    release: monitoring    # Must match Prometheus selector
spec:
  selector:
    matchLabels:
      app: cleerly-api
  namespaceSelector:
    matchNames:
      - production
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
EOF

# PrometheusRule: pre-compute SLO recording rules
cat << 'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cleerly-slo-rules
  namespace: monitoring
  labels:
    release: monitoring
spec:
  groups:
    - name: cleerly.api.slo
      interval: 30s
      rules:
        # Request rate
        - record: job:http_requests:rate5m
          expr: sum(rate(http_requests_total{job="cleerly-api"}[5m])) by (job)

        # Error rate
        - record: job:http_errors:rate5m
          expr: sum(rate(http_requests_total{job="cleerly-api",status=~"5.."}[5m])) by (job)

        # Error ratio (for SLO burn rate alerts)
        - record: job:http_error_ratio:rate5m
          expr: job:http_errors:rate5m / job:http_requests:rate5m

        # p99 latency
        - record: job:http_latency_p99:rate5m
          expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job="cleerly-api"}[5m]))

    - name: cleerly.api.alerts
      rules:
        - alert: HighErrorRate
          expr: job:http_error_ratio:rate5m > 0.01
          for: 5m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "High error rate on cleerly-api"
            description: "Error ratio is {{ $value | humanizePercentage }} over last 5m"
EOF
```

---

## Interview Talking Points

**"Why Karpenter over the Cluster Autoscaler?"**
Cluster Autoscaler works at the node group level and can only scale pre-defined instance types. Karpenter provisions individual nodes in under 60 seconds by directly calling the EC2 fleet API, picks the optimal instance type from a family of options based on pending pod requirements, and consolidates underutilized nodes automatically. For a workload mix that includes both general API pods and occasional GPU inference jobs, that flexibility cuts infrastructure costs significantly compared to maintaining separate autoscaling groups.

**"What does `consolidateAfter: 30s` mean and why is it aggressive?"**
It tells Karpenter to bin-pack and terminate underutilized nodes 30 seconds after they become consolidation candidates. In a cloud-native environment with proper PodDisruptionBudgets, this is safe and keeps the fleet lean. The `expireAfter: 720h` (30-day TTL) ensures nodes are regularly cycled through for OS and AMI patch updates — important for HIPAA where unpatched nodes are a compliance finding.

**"How does kube-prometheus-stack differ from running Prometheus manually?"**
The Helm chart ships Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, and a full set of default alerting rules pre-wired together. More importantly, it installs the Prometheus Operator CRDs — `ServiceMonitor`, `PodMonitor`, `PrometheusRule` — which let you configure scraping and alerting as Kubernetes objects alongside your application manifests, rather than editing a central Prometheus config file.

**"Walk me through your zero-downtime EKS upgrade process."**
Four steps in order: (1) run Pluto to detect any deprecated API versions in your manifests before the upgrade — a v1.25 cluster won't serve `PodSecurityPolicy` resources, for example; (2) upgrade the control plane, which is AWS-managed and non-disruptive; (3) update the EKS add-ons (CoreDNS, kube-proxy, VPC CNI) to versions compatible with the new control plane; (4) drain and replace managed node groups — AWS does this rolling, one node at a time, respecting PodDisruptionBudgets. Workloads stay up throughout.

**"What are recording rules and why do they matter at scale?"**
Recording rules pre-compute expensive PromQL expressions on a schedule and store the result as a new metric. Without them, a Grafana dashboard with 10 panels each running a `rate()` over 30 days would hit Prometheus with expensive range queries on every page load. Pre-aggregated rules make dashboards fast and reduce Prometheus query load, which matters when you're storing 30 days of metrics at 30-second resolution across hundreds of pods.

## Step 5 — EKS Cluster Version Upgrade (Zero-Downtime)

```bash
export CLUSTER_NAME=cleerly-prod
export NEW_VERSION=1.31

# Pre-upgrade: check deprecated APIs
kubectl convert -f ./k8s/ --output-version apps/v1 2>&1 | grep -i deprecated

# Install Pluto to detect deprecated k8s APIs in your manifests
brew install pluto
pluto detect-files -d ./k8s --target-versions k8s=v1.31.0

# Step 1: Update EKS control plane
aws eks update-cluster-version \
  --name $CLUSTER_NAME \
  --kubernetes-version $NEW_VERSION

# Monitor upgrade progress (takes ~10-15 min)
watch aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query "cluster.{Status:status,Version:version}" \
  --output table

# Step 2: Update add-ons (must be done after control plane)
for ADDON in coredns kube-proxy vpc-cni; do
  LATEST=$(aws eks describe-addon-versions \
    --addon-name $ADDON \
    --kubernetes-version $NEW_VERSION \
    --query "addons[0].addonVersions[0].addonVersion" \
    --output text)
  aws eks update-addon \
    --cluster-name $CLUSTER_NAME \
    --addon-name $ADDON \
    --addon-version $LATEST \
    --resolve-conflicts OVERWRITE
  echo "Updated $ADDON to $LATEST"
done

# Step 3: Update managed node groups (rolling)
aws eks update-nodegroup-version \
  --cluster-name $CLUSTER_NAME \
  --nodegroup-name general \
  --kubernetes-version $NEW_VERSION

# Step 4: Validate all workloads post-upgrade
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
kubectl top nodes
kubectl get events --sort-by=.lastTimestamp | tail -20
```
