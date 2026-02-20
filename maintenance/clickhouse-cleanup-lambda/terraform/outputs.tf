output "lambda_function_arn" {
  description = "ARN of the ClickHouse cleanup Lambda function"
  value       = aws_lambda_function.cleanup.arn
}

output "lambda_function_name" {
  description = "Name of the ClickHouse cleanup Lambda function"
  value       = aws_lambda_function.cleanup.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda.arn
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the ClickHouse PVC CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.clickhouse_pvc.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.pvc_alarm.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.pvc_alarm.arn
}
