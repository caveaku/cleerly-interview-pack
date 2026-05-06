# HIPAA / SOC 2 required AWS Config Rules
# Deploy with: terraform apply

locals {
  hipaa_config_rules = [
    "EKS_ENDPOINT_NO_PUBLIC_ACCESS",
    "ENCRYPTED_VOLUMES",
    "RDS_STORAGE_ENCRYPTED",
    "S3_BUCKET_PUBLIC_READ_PROHIBITED",
    "S3_BUCKET_PUBLIC_WRITE_PROHIBITED",
    "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED",
    "CLOUDTRAIL_ENABLED",
    "CLOUDTRAIL_LOG_FILE_VALIDATION_ENABLED",
    "IAM_ROOT_ACCESS_KEY_CHECK",
    "IAM_USER_MFA_ENABLED",
    "GUARDDUTY_ENABLED_CENTRALIZED",
    "VPC_FLOW_LOGS_ENABLED",
  ]
}

resource "aws_config_config_rule" "hipaa_rules" {
  for_each = toset(local.hipaa_config_rules)

  name = "cleerly-${lower(replace(each.value, "_", "-"))}"

  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  tags = {
    Compliance  = "HIPAA"
    ManagedBy   = "terraform"
    Environment = "prod"
  }
}

# Auto-remediation for S3 public access violations
resource "aws_config_remediation_configuration" "s3_public_read" {
  config_rule_name = aws_config_config_rule.hipaa_rules["S3_BUCKET_PUBLIC_READ_PROHIBITED"].name

  resource_type  = "AWS::S3::Bucket"
  target_type    = "SSM_DOCUMENT"
  target_id      = "AWS-DisableS3BucketPublicReadWrite"
  automatic      = true

  maximum_automatic_attempts = 3
  retry_attempt_seconds      = 60

  parameter {
    name           = "AutomationAssumeRole"
    static_value   = aws_iam_role.config_remediation.arn
  }
}

resource "aws_iam_role" "config_remediation" {
  name = "cleerly-config-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_remediation" {
  role       = aws_iam_role.config_remediation.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
