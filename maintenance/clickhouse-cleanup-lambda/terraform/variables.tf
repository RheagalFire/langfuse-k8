variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name (used in CloudWatch alarm dimensions)"
  type        = string
  default     = "langfuse-cluster"
}

# --- Networking ---

variable "subnet_ids" {
  description = <<-EOT
    Private subnet IDs in the EKS VPC. Lambda must be in the same VPC as EKS
    to reach the ClickHouse NodePort.

    Lookup:
      VPC_ID=$(aws eks describe-cluster --name langfuse-cluster \
        --query "cluster.resourcesVpcConfig.vpcId" --output text)
      aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[?MapPublicIpOnLaunch==\`false\`].[SubnetId,AvailabilityZone]" \
        --output table
  EOT
  type        = list(string)
}

variable "security_group_ids" {
  description = <<-EOT
    Security group IDs for the Lambda VPC config. Simplest option: reuse the
    EKS cluster security group.

    Lookup (cluster SG):
      aws eks describe-cluster --name langfuse-cluster \
        --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text

    IMPORTANT: The ClickHouse node's security group must allow inbound TCP
    on port 30123 (NodePort) from this security group.
  EOT
  type        = list(string)
}

# --- ClickHouse ---

variable "clickhouse_host" {
  description = <<-EOT
    Private IP of the ClickHouse node. This is the INTERNAL-IP of the node
    running the ClickHouse pod. Note: this IP changes if the node is replaced
    (e.g. scaling event, node recycle). For production stability consider an
    NLB or DNS record in front of the node.

    Lookup:
      kubectl get nodes -l nodegroup=clickhouse -o wide
      # Use the INTERNAL-IP column
  EOT
  type        = string
}

variable "clickhouse_port" {
  description = "ClickHouse HTTP port (NodePort exposed by clickhouse-nodeport.yaml)"
  type        = string
  default     = "30123"
}

variable "clickhouse_password" {
  description = <<-EOT
    ClickHouse default user password. Currently passed as a plaintext Lambda
    environment variable. For production, consider storing in AWS SSM Parameter
    Store (SecureString) and reading at runtime in the Lambda function.
  EOT
  type        = string
  sensitive   = true
}

# --- Retention ---

variable "retention_days_app" {
  description = "Days to retain application data (observations, traces)"
  type        = number
  default     = 30
}

variable "retention_days_system" {
  description = "Days to retain ClickHouse system logs"
  type        = number
  default     = 10
}

# --- Alarm ---

variable "alarm_threshold" {
  description = "PVC usage percentage threshold to trigger the alarm"
  type        = number
  default     = 90
}

variable "notification_email" {
  description = "Email address for SNS alarm notifications (leave empty to skip)"
  type        = string
  default     = ""
}

# --- Lambda layer ---

variable "requests_layer_arn" {
  description = "ARN of a Lambda layer providing the 'requests' library (e.g. Klayers-p312-requests). Leave empty if bundled in the zip."
  type        = string
  default     = ""
}
