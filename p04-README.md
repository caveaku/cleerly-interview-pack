# Project 04 — HIPAA / HITRUST / SOC 2 Compliance Guardrails on AWS

## Objective
Automate continuous compliance using AWS Security Hub, Config, GuardDuty, CloudTrail, and IAM.
Demonstrates regulated environment experience critical for Cleerly's health tech platform.

## JD Alignment
> "Proactively identify and remediate security gaps in infrastructure, IAM policies, and DevOps tooling"
> "Ensure alignment with compliance standards (HIPAA, HITRUST, SOC 2)"

---

## Step 1 — Enable AWS Security Hub with HIPAA Standard

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Enable Security Hub
aws securityhub enable-security-hub \
  --enable-default-standards \
  --region $AWS_REGION

# Enable HIPAA compliance standard
aws securityhub batch-enable-standards \
  --standards-subscription-requests \
    StandardsArn=arn:aws:securityhub:$AWS_REGION::standards/hipaa-aws-risk-and-authorization-management-program/v/1.0.0

# Enable AWS Foundational Security Best Practices (FSBP)
aws securityhub batch-enable-standards \
  --standards-subscription-requests \
    StandardsArn=arn:aws:securityhub:$AWS_REGION::standards/aws-foundational-security-best-practices/v/1.0.0

# Get compliance score
aws securityhub get-findings \
  --filters '{"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}]}' \
  --query "Findings[*].{Title:Title,Severity:Severity.Label,Resource:Resources[0].Id}" \
  --output table | head -30

# Aggregate findings across all accounts (if multi-account)
aws securityhub enable-organization-admin-account \
  --admin-account-id $AWS_ACCOUNT_ID
```

---

## Step 2 — Enable GuardDuty with Full Protection

```bash
# Enable GuardDuty with all protection plans
aws guardduty create-detector \
  --enable \
  --data-sources '{
    "S3Logs": {"Enable": true},
    "Kubernetes": {"AuditLogs": {"Enable": true}},
    "MalwareProtection": {"ScanEc2InstanceWithFindings": {"EbsVolumes": true}}
  }' \
  --features '[
    {"Name": "EKS_AUDIT_LOGS", "Status": "ENABLED"},
    {"Name": "S3_DATA_EVENTS", "Status": "ENABLED"},
    {"Name": "EKS_RUNTIME_MONITORING", "Status": "ENABLED"}
  ]' \
  --region $AWS_REGION

# Get detector ID
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
echo "Detector ID: $DETECTOR_ID"

# Set up SNS notification for High/Critical findings
aws guardduty create-threat-intel-set \
  --detector-id $DETECTOR_ID \
  --name cleerly-threat-intel \
  --format TXT \
  --location s3://cleerly-security/threat-intel/known-bad-ips.txt \
  --activate

# List active findings
aws guardduty list-findings \
  --detector-id $DETECTOR_ID \
  --finding-criteria '{
    "Criterion": {
      "severity": {"Gte": 7}
    }
  }' \
  --query "FindingIds"
```

---

## Step 3 — Deploy AWS Config Rules for Continuous Compliance

```bash
# Enable AWS Config recorder
aws configservice put-configuration-recorder \
  --configuration-recorder '{
    "name": "default",
    "roleARN": "arn:aws:iam::'$AWS_ACCOUNT_ID':role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig",
    "recordingGroup": {
      "allSupported": true,
      "includeGlobalResourceTypes": true
    }
  }'

# Enable Config delivery channel
aws configservice put-delivery-channel \
  --delivery-channel '{
    "name": "default",
    "s3BucketName": "cleerly-config-logs",
    "configSnapshotDeliveryProperties": {
      "deliveryFrequency": "One_Hour"
    }
  }'

aws configservice start-configuration-recorder \
  --configuration-recorder-name default

# Deploy managed Config rules for HIPAA
CONFIG_RULES=(
  "EKS_ENDPOINT_NO_PUBLIC_ACCESS"
  "ENCRYPTED_VOLUMES"
  "RDS_STORAGE_ENCRYPTED"
  "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
  "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  "CLOUDTRAIL_ENABLED"
  "CLOUDTRAIL_LOG_FILE_VALIDATION_ENABLED"
  "IAM_ROOT_ACCESS_KEY_CHECK"
  "IAM_USER_MFA_ENABLED"
  "GUARDDUTY_ENABLED_CENTRALIZED"
  "VPC_FLOW_LOGS_ENABLED"
)

for RULE in "${CONFIG_RULES[@]}"; do
  echo "Creating Config rule: $RULE"
  aws configservice put-config-rule \
    --config-rule "{
      \"ConfigRuleName\": \"cleerly-$(echo $RULE | tr '[:upper:]' '[:lower:]' | tr '_' '-')\",
      \"Source\": {
        \"Owner\": \"AWS\",
        \"SourceIdentifier\": \"$RULE\"
      }
    }"
done

# Check compliance status
aws configservice describe-compliance-by-config-rule \
  --compliance-types NON_COMPLIANT \
  --query "ComplianceByConfigRules[*].{Rule:ConfigRuleName,Status:Compliance.ComplianceType}" \
  --output table
```

---

## Step 4 — Configure CloudTrail with Integrity Validation

```bash
# Create S3 bucket for audit logs with object lock (HIPAA: 6yr retention)
aws s3api create-bucket \
  --bucket cleerly-audit-logs \
  --object-lock-enabled-for-bucket \
  --region $AWS_REGION

# Block all public access
aws s3api put-public-access-block \
  --bucket cleerly-audit-logs \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Set object lock to COMPLIANCE mode (cannot be deleted by anyone)
aws s3api put-object-lock-configuration \
  --bucket cleerly-audit-logs \
  --object-lock-configuration '{
    "ObjectLockEnabled": "Enabled",
    "Rule": {
      "DefaultRetention": {
        "Mode": "COMPLIANCE",
        "Years": 6
      }
    }
  }'

# Enable KMS encryption
aws s3api put-bucket-encryption \
  --bucket cleerly-audit-logs \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/cleerly-cloudtrail-key"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Create multi-region CloudTrail
aws cloudtrail create-trail \
  --name cleerly-audit-trail \
  --s3-bucket-name cleerly-audit-logs \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation \
  --cloud-watch-logs-log-group-arn arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:cloudtrail \
  --cloud-watch-logs-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/CloudTrailCWRole \
  --kms-key-id alias/cleerly-cloudtrail-key

aws cloudtrail start-logging --name cleerly-audit-trail

# Verify log file integrity
aws cloudtrail validate-logs \
  --trail-arn arn:aws:cloudtrail:$AWS_REGION:$AWS_ACCOUNT_ID:trail/cleerly-audit-trail \
  --start-time "2025-01-01T00:00:00Z"
```

---

## Step 5 — Implement IAM Least-Privilege with Permission Boundaries

```bash
# Create permission boundary policy for all DevOps engineers
cat > devops-boundary.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDevOpsServices",
      "Effect": "Allow",
      "Action": [
        "ec2:*", "eks:*", "ecr:*", "s3:*",
        "cloudwatch:*", "logs:*", "ssm:*",
        "ecs:*", "elasticloadbalancing:*",
        "autoscaling:*", "kms:Describe*", "kms:List*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2"]
        }
      }
    },
    {
      "Sid": "DenyPrivilegeEscalation",
      "Effect": "Deny",
      "Action": [
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "organizations:*",
        "account:*",
        "sts:AssumeRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyModifyBoundary",
      "Effect": "Deny",
      "Action": [
        "iam:DeleteUserPermissionsBoundary",
        "iam:DeleteRolePermissionsBoundary"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name ClearlyDevOpsBoundary \
  --policy-document file://devops-boundary.json

# Attach boundary when creating engineer roles
aws iam create-role \
  --role-name DevOpsEngineerRole \
  --assume-role-policy-document file://trust-policy.json \
  --permissions-boundary arn:aws:iam::$AWS_ACCOUNT_ID:policy/ClearlyDevOpsBoundary

# Auto-remediation: Lambda to enforce boundary on new roles
aws lambda create-function \
  --function-name enforce-permission-boundary \
  --runtime python3.12 \
  --handler lambda_function.lambda_handler \
  --role arn:aws:iam::$AWS_ACCOUNT_ID:role/LambdaEnforceBoundaryRole \
  --zip-file fileb://enforce-boundary.zip

# EventBridge rule: trigger on any new IAM role creation
aws events put-rule \
  --name enforce-iam-boundary \
  --event-pattern '{
    "source": ["aws.iam"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {"eventName": ["CreateRole"]}
  }' \
  --state ENABLED
```

---

## Compliance Verification Commands

```bash
# Security Hub compliance score
aws securityhub get-findings \
  --filters '{
    "ComplianceStatus": [{"Value":"PASSED","Comparison":"EQUALS"}],
    "WorkflowStatus": [{"Value":"NEW","Comparison":"EQUALS"}]
  }' \
  --query "length(Findings)"

# GuardDuty high-severity findings
aws guardduty get-findings \
  --detector-id $DETECTOR_ID \
  --finding-ids $(aws guardduty list-findings \
    --detector-id $DETECTOR_ID \
    --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}' \
    --query "FindingIds[0]" --output text)

# Config compliance summary
aws configservice get-compliance-summary-by-config-rule \
  --query "ComplianceSummary.{Compliant:CompliantResourceCount.CappedCount,NonCompliant:NonCompliantResourceCount.CappedCount}"

# IAM Access Analyzer — detect unintended public access
aws accessanalyzer create-analyzer \
  --analyzer-name cleerly-account-analyzer \
  --type ACCOUNT

aws accessanalyzer list-findings \
  --analyzer-name cleerly-account-analyzer \
  --filter '{"status": {"eq": ["ACTIVE"]}}' \
  --query "findings[*].{Resource:resource,Type:findingType,Public:isPublic}"
```
