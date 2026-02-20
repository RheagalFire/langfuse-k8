###############################################################################
# Langfuse ClickHouse Cleanup — Lambda + CloudWatch Alarm + EventBridge
#
# This Terraform creates the full maintenance pipeline:
#   PVC Monitor CronJob → CloudWatch metric → Alarm → EventBridge → Lambda
#
# The PVC monitor CronJob (already deployed in K8s) pushes UsagePercent to
# CloudWatch. When ClickHouse PVC exceeds the threshold, the alarm triggers
# EventBridge which invokes the Lambda to delete old data.
###############################################################################
#
# Prerequisites — the following must exist before running terraform apply:
#
#   1. EKS cluster running with the ClickHouse NodePort service applied
#      (manifests/clickhouse-nodeport.yaml → exposes port 30123)
#
#   2. VPC ID and private subnet IDs from the EKS cluster:
#        aws eks describe-cluster --name langfuse-cluster \
#          --query "cluster.resourcesVpcConfig.{VpcId:vpcId,Subnets:subnetIds}"
#
#   3. Security group ID — either the EKS cluster SG or a dedicated one:
#        aws eks describe-cluster --name langfuse-cluster \
#          --query "cluster.resourcesVpcConfig.clusterSecurityGroupId"
#
#   4. ClickHouse node private IP:
#        kubectl get nodes -l nodegroup=clickhouse -o wide  # INTERNAL-IP column
#
#   5. ClickHouse default user password (from langfuse-secrets K8s Secret)
#
#   6. (Optional) Lambda layer ARN providing the 'requests' library
#      e.g. Klayers-p312-requests for your region
#
###############################################################################

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################################
# Data sources
###############################################################################

data "aws_caller_identity" "current" {}

###############################################################################
# IAM Role for Lambda
###############################################################################

resource "aws_iam_role" "lambda" {
  name = "langfuse-clickhouse-cleanup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

###############################################################################
# Lambda function
###############################################################################

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "cleanup" {
  function_name    = "langfuse-clickhouse-cleanup"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 180
  memory_size      = 1024
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  layers = var.requests_layer_arn != "" ? [var.requests_layer_arn] : []

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = {
      CLICKHOUSE_HOST       = var.clickhouse_host
      CLICKHOUSE_PORT       = var.clickhouse_port
      CLICKHOUSE_PASSWORD   = var.clickhouse_password
      RETENTION_DAYS_APP    = tostring(var.retention_days_app)
      RETENTION_DAYS_SYSTEM = tostring(var.retention_days_system)
    }
  }
}

###############################################################################
# SNS Topic for alarm notifications
###############################################################################

resource "aws_sns_topic" "pvc_alarm" {
  name = "langfuse-clickhouse-pvc-alarm"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.pvc_alarm.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

###############################################################################
# CloudWatch Alarm — ClickHouse PVC usage
###############################################################################

resource "aws_cloudwatch_metric_alarm" "clickhouse_pvc" {
  alarm_name          = "langfuse-clickhouse-pvc-usage"
  alarm_description   = "ClickHouse PVC usage exceeds ${var.alarm_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UsagePercent"
  namespace           = "LangfusePVC"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.alarm_threshold

  dimensions = {
    ClusterName = var.cluster_name
    Namespace   = "langfuse"
    PVCName     = "data-langfuse-clickhouse-shard0-0"
    PodName     = "langfuse-clickhouse-shard0-0"
  }

  alarm_actions = [aws_sns_topic.pvc_alarm.arn]
  ok_actions    = [aws_sns_topic.pvc_alarm.arn]
}

###############################################################################
# EventBridge Rule — trigger Lambda when alarm fires
###############################################################################

resource "aws_cloudwatch_event_rule" "pvc_alarm" {
  name        = "langfuse-clickhouse-pvc-cleanup"
  description = "Trigger ClickHouse cleanup when PVC alarm enters ALARM state"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [aws_cloudwatch_metric_alarm.clickhouse_pvc.alarm_name]
      state = {
        value = ["ALARM"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.pvc_alarm.name
  arn  = aws_lambda_function.cleanup.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pvc_alarm.arn
}
