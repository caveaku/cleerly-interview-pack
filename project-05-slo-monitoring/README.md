# Project 05 — SLO/SLA Monitoring & Incident Response

## Objective
Define error budgets, build CloudWatch composite alarms, automate runbook execution with SSM,
and produce post-incident review dashboards. Demonstrates full reliability engineering lifecycle.

## JD Alignment
> "Define and track SLAs/SLOs in partnership with product and engineering teams"
> "Participate in on-call rotations and lead post-incident reviews"
> "Driving long-term reliability improvements across systems"

---

## Step 1 — Define SLOs as Code (Sloth / Pyrra)

```bash
# Install Sloth — SLO framework for Prometheus
helm repo add sloth https://sloth.dev/helm-charts
helm install sloth sloth/sloth \
  --namespace monitoring \
  --set commonLabels.release=monitoring

# Apply SLO definitions
cat << 'EOF' | kubectl apply -f -
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: cleerly-api-slos
  namespace: monitoring
spec:
  service: cleerly-api

  labels:
    team: platform
    env: prod

  slos:
    # SLO 1: API Availability — 99.9% uptime
    - name: requests-availability
      objective: 99.9
      description: "99.9% of API requests succeed (non-5xx)"
      sli:
        events:
          errorQuery: sum(rate(http_requests_total{job="cleerly-api",status=~"5.."}[{{.window}}]))
          totalQuery: sum(rate(http_requests_total{job="cleerly-api"}[{{.window}}]))
      alerting:
        name: ClearlyAPIHighErrorRate
        labels:
          category: availability
        annotations:
          runbook: https://wiki.cleerly.com/runbooks/api-high-error-rate
        pageAlert:
          labels:
            severity: critical
        ticketAlert:
          labels:
            severity: warning

    # SLO 2: CT Scan Processing Latency — p99 < 30s
    - name: scan-latency
      objective: 99.5
      description: "99.5% of CT scans processed within 30 seconds"
      sli:
        events:
          errorQuery: |
            sum(rate(scan_processing_duration_seconds_bucket{
              job="cleerly-scan-processor",
              le="30"
            }[{{.window}}]))
          totalQuery: |
            sum(rate(scan_processing_duration_seconds_count{
              job="cleerly-scan-processor"
            }[{{.window}}]))
      alerting:
        name: CleerlyScanLatencyHigh
        annotations:
          runbook: https://wiki.cleerly.com/runbooks/scan-latency
        pageAlert:
          labels:
            severity: critical
EOF

# Check generated recording rules
kubectl get prometheusrules -n monitoring
```

---

## Step 2 — Error Budget Calculation & Tracking

```bash
# Calculate current error budget remaining (Prometheus query)
# Formula: budget_remaining = 1 - (error_rate / (1 - SLO_target))

# Query via promtool (local testing)
cat << 'EOF' > error-budget-query.promql
# Error budget consumed in last 30 days
(
  1 - (
    sum(rate(http_requests_total{job="cleerly-api",status!~"5.."}[30d]))
    /
    sum(rate(http_requests_total{job="cleerly-api"}[30d]))
  )
) / (1 - 0.999)  # Divide by error budget (0.001 = 0.1%)
EOF

# Burn rate alerts (multi-window, multi-burn-rate strategy)
cat << 'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cleerly-burn-rate-alerts
  namespace: monitoring
spec:
  groups:
    - name: cleerly.burnrate
      rules:
        # Fast burn: consuming 14.4x budget over 1h → page immediately
        - alert: ClearlyAPIBurnRateFast
          expr: |
            (
              job:http_error_ratio:rate1h{job="cleerly-api"} > (14.4 * 0.001)
              AND
              job:http_error_ratio:rate5m{job="cleerly-api"} > (14.4 * 0.001)
            )
          for: 2m
          labels:
            severity: critical
            page: "true"
          annotations:
            summary: "CRITICAL: API burning error budget at 14.4x rate"
            description: "Will exhaust monthly budget in ~2 hours"

        # Slow burn: consuming 6x budget over 6h → ticket
        - alert: ClearlyAPIBurnRateSlow
          expr: |
            (
              job:http_error_ratio:rate6h{job="cleerly-api"} > (6 * 0.001)
              AND
              job:http_error_ratio:rate30m{job="cleerly-api"} > (6 * 0.001)
            )
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "WARNING: API burning error budget at 6x rate"
            description: "Will exhaust monthly budget in ~5 days"
EOF
```

---

## Step 3 — CloudWatch Composite Alarms (Reduce Alert Fatigue)

```bash
export AWS_REGION=us-east-1
export SNS_CRITICAL=arn:aws:sns:us-east-1:123456789012:cleerly-pagerduty-critical
export SNS_WARNING=arn:aws:sns:us-east-1:123456789012:cleerly-pagerduty-warning
export ALB_NAME=cleerly-prod

# Individual metric alarms
aws cloudwatch put-metric-alarm \
  --alarm-name "API-5xx-Rate-High" \
  --metric-name "5XXError" \
  --namespace AWS/ApplicationELB \
  --dimensions Name=LoadBalancer,Value=$ALB_NAME \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 10 \
  --statistic Sum \
  --comparison-operator GreaterThanThreshold

aws cloudwatch put-metric-alarm \
  --alarm-name "EKS-Node-CPU-Critical" \
  --metric-name "node_cpu_utilization" \
  --namespace ContainerInsights \
  --dimensions Name=ClusterName,Value=cleerly-prod \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 90 \
  --statistic Average \
  --comparison-operator GreaterThanThreshold

aws cloudwatch put-metric-alarm \
  --alarm-name "RDS-Connection-Exhausted" \
  --metric-name "DatabaseConnections" \
  --namespace AWS/RDS \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 450 \
  --statistic Average \
  --comparison-operator GreaterThanThreshold

# Composite alarm: only page when correlated signals fire together
aws cloudwatch put-composite-alarm \
  --alarm-name "P1-Production-Degradation" \
  --alarm-rule \
    "ALARM(API-5xx-Rate-High) AND (ALARM(EKS-Node-CPU-Critical) OR ALARM(RDS-Connection-Exhausted))" \
  --alarm-actions $SNS_CRITICAL \
  --ok-actions $SNS_CRITICAL \
  --alarm-description "P1: Production service degradation — multiple correlated signals"

# Verify composite alarm
aws cloudwatch describe-alarms \
  --alarm-names "P1-Production-Degradation" \
  --query "CompositeAlarms[0].{State:StateValue,Rule:AlarmRule}"
```

---

## Step 4 — Automate Runbook Execution with SSM Automation

```bash
# Create SSM document for pod restart runbook
cat > runbook-restart-pods.json << 'EOF'
{
  "schemaVersion": "0.3",
  "description": "Runbook: Identify and restart unhealthy EKS pods in production",
  "assumeRole": "{{ AutomationAssumeRole }}",
  "parameters": {
    "Namespace": {
      "type": "String",
      "default": "production"
    },
    "DeploymentName": {
      "type": "String",
      "description": "Name of the deployment to restart"
    },
    "AutomationAssumeRole": {
      "type": "AWS::IAM::Role::Arn"
    }
  },
  "mainSteps": [
    {
      "name": "CheckClusterHealth",
      "action": "aws:executeScript",
      "inputs": {
        "Runtime": "python3.8",
        "Handler": "check_health",
        "Script": "def check_health(events, context):\n    import subprocess\n    result = subprocess.run(['kubectl','get','pods','-n',events['Namespace'],'--field-selector=status.phase!=Running','-o','wide'], capture_output=True, text=True)\n    return {'unhealthy_pods': result.stdout, 'returncode': result.returncode}",
        "InputPayload": {
          "Namespace": "{{ Namespace }}"
        }
      },
      "outputs": [
        {"Name": "unhealthy_pods", "Selector": "$.Payload.unhealthy_pods", "Type": "String"}
      ]
    },
    {
      "name": "RolloutRestart",
      "action": "aws:executeScript",
      "inputs": {
        "Runtime": "python3.8",
        "Handler": "restart",
        "Script": "def restart(events, context):\n    import subprocess\n    subprocess.run(['kubectl','rollout','restart','deployment/'+events['Deployment'],'-n',events['Namespace']])\n    result = subprocess.run(['kubectl','rollout','status','deployment/'+events['Deployment'],'-n',events['Namespace'],'--timeout=300s'], capture_output=True, text=True)\n    return {'status': result.stdout}",
        "InputPayload": {
          "Namespace": "{{ Namespace }}",
          "Deployment": "{{ DeploymentName }}"
        }
      }
    }
  ]
}
EOF

aws ssm create-document \
  --name "Cleerly-RestartUnhealthyPods" \
  --document-type Automation \
  --document-format JSON \
  --content file://runbook-restart-pods.json

# Test the runbook
aws ssm start-automation-execution \
  --document-name "Cleerly-RestartUnhealthyPods" \
  --parameters '{
    "Namespace": ["production"],
    "DeploymentName": ["cleerly-api"],
    "AutomationAssumeRole": ["arn:aws:iam::123456789012:role/SSMAutomationRole"]
  }'

# Monitor execution
aws ssm describe-automation-executions \
  --filters Key=DocumentNamePrefix,Values=Cleerly \
  --query "AutomationExecutionMetadataList[0].{Status:AutomationExecutionStatus,Start:ExecutionStartTime}"
```

---

## Step 5 — Post-Incident Review (PIR) Dashboard & Template

```bash
# Create annotated CloudWatch dashboard for PIR
aws cloudwatch put-dashboard \
  --dashboard-name "Cleerly-PostIncidentReview" \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "x": 0, "y": 0, "width": 24, "height": 8,
        "properties": {
          "title": "API Error Rate — Incident Timeline",
          "metrics": [
            ["AWS/ApplicationELB", "5XXError", "LoadBalancer", "cleerly-prod",
             {"stat": "Sum", "color": "#d62728", "label": "5XX Errors"}],
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "cleerly-prod",
             {"stat": "Sum", "color": "#1f77b4", "yAxis": "right", "label": "Total Requests"}]
          ],
          "period": 60,
          "view": "timeSeries",
          "stacked": false,
          "annotations": {
            "vertical": [
              {
                "label": "Incident Detected",
                "value": "2025-04-15T14:00:00.000Z",
                "color": "#d62728"
              },
              {
                "label": "Mitigation Applied",
                "value": "2025-04-15T14:45:00.000Z",
                "color": "#ff7f0e"
              },
              {
                "label": "Fully Resolved",
                "value": "2025-04-15T15:30:00.000Z",
                "color": "#2ca02c"
              }
            ]
          }
        }
      },
      {
        "type": "metric",
        "x": 0, "y": 8, "width": 12, "height": 6,
        "properties": {
          "title": "EKS Node CPU During Incident",
          "metrics": [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", "cleerly-prod"]
          ],
          "period": 60,
          "stat": "Average"
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 8, "width": 12, "height": 6,
        "properties": {
          "title": "RDS Connections During Incident",
          "metrics": [
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", "cleerly-prod-db"]
          ],
          "period": 60,
          "stat": "Maximum"
        }
      }
    ]
  }'

echo "PIR Dashboard created. View at:"
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=Cleerly-PostIncidentReview"
```

---

## Interview Talking Points

**"How do you explain an error budget to a non-technical stakeholder?"**
An SLO of 99.9% means we allow 43 minutes of downtime per month — that's the error budget. We spend it on risky deployments, experiments, and incidents. When the budget is full, engineering has earned the right to move fast. When it's nearly empty, we freeze releases and focus on reliability. It turns reliability into a shared language between product and engineering instead of a vague aspiration.

**"Why multi-window multi-burn-rate alerts instead of a simple error threshold?"**
A fixed threshold like "alert if error rate > 1% for 5 minutes" either fires too often on transient spikes (alert fatigue) or misses slow-burn incidents that drain the budget over days without crossing the threshold. Multi-window burn rate alerts fire when you're consuming budget significantly faster than normal — a 14.4x burn rate over 1 hour means you'll exhaust the monthly budget in 2 hours, which is always worth a page regardless of the absolute error rate.

**"Why CloudWatch composite alarms instead of individual alarms per metric?"**
Individual alarms create noise — an elevated CPU alarm fires dozens of times during normal traffic spikes. A composite alarm requires correlated signals: `5xx errors high AND (CPU critical OR DB connections exhausted)`. This pattern mirrors how incidents actually manifest and cuts on-call pages by requiring that multiple independent signals confirm a real production degradation before waking someone up at 2am.

**"What's the value of SSM Automation runbooks over a wiki page?"**
Wiki runbooks go stale, are skipped under pressure, and leave no audit trail. SSM Automation runbooks are executable, version-controlled, and produce a structured execution log in AWS showing exactly which steps ran, when, and what the output was. In a HIPAA environment that needs audit trails for system actions, automated runbooks are the difference between "we followed the procedure" and "here's the CloudTrail-verified proof we followed the procedure."

**"How do you run a post-incident review?"**
I use a blameless PIR format: timeline (detection → mitigation → resolution), contributing factors (not root cause — complex systems rarely have one), what worked well, and action items with owners and due dates. The CloudWatch dashboard with incident annotations gives the team a visual timeline to anchor the discussion. I track PIR action items in the same backlog as feature work — if they're in a separate doc, they never get done.

**"What SLOs would you define for a CT scan processing service like Cleerly's?"**
Two primary ones: availability (99.9% of scans successfully processed) and latency (99.5% of scans return results within 30 seconds). I'd also add a data freshness SLO if results feed a downstream dashboard. The 30-second latency threshold is domain-specific — it maps to what a radiologist workflow can tolerate before the tool becomes an obstacle rather than an accelerator.

## Validation & Error Budget Status

```bash
# Check current error budget burn via CloudWatch Metrics Insights
aws cloudwatch get_metric_data \
  --metric-data-queries '[
    {
      "Id": "errorRate",
      "Expression": "errors / requests * 100",
      "Label": "Error Rate %"
    },
    {
      "Id": "errors",
      "MetricStat": {
        "Metric": {
          "Namespace": "AWS/ApplicationELB",
          "MetricName": "5XXError",
          "Dimensions": [{"Name": "LoadBalancer", "Value": "cleerly-prod"}]
        },
        "Period": 86400,
        "Stat": "Sum"
      },
      "ReturnData": false
    },
    {
      "Id": "requests",
      "MetricStat": {
        "Metric": {
          "Namespace": "AWS/ApplicationELB",
          "MetricName": "RequestCount",
          "Dimensions": [{"Name": "LoadBalancer", "Value": "cleerly-prod"}]
        },
        "Period": 86400,
        "Stat": "Sum"
      },
      "ReturnData": false
    }
  ]' \
  --start-time $(date -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date +%Y-%m-%dT%H:%M:%SZ)

# Check all CloudWatch alarms status
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query "MetricAlarms[*].{Alarm:AlarmName,Reason:StateReason}" \
  --output table

# List SSM runbook execution history
aws ssm describe-automation-executions \
  --filters Key=DocumentNamePrefix,Values=Cleerly \
  --query "AutomationExecutionMetadataList[*].{Name:DocumentName,Status:AutomationExecutionStatus,Time:ExecutionStartTime}" \
  --output table
```
