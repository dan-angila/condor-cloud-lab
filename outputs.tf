output "api_url" {
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
  description = "Condor API Gateway URL"
}

output "lambda_name" {
  value       = aws_lambda_function.api.function_name
  description = "Lambda function name"
}

output "dynamodb_table" {
  value       = aws_dynamodb_table.users.name
  description = "DynamoDB users table name"
}

output "jobs_queue_url" {
  value       = aws_sqs_queue.jobs.url
  description = "SQS jobs queue URL"
}

output "app_storage_bucket" {
  value       = aws_s3_bucket.app_storage.bucket
  description = "S3 app storage bucket name"
}

output "alerts_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "SNS alerts topic ARN"
}

output "ec2_instance_id" {
  value       = aws_instance.web.id
  description = "EC2 instance ID"
}

output "ec2_public_ip" {
  value       = aws_eip.web.public_ip
  description = "EC2 instance public IP"
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}

output "current_aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Current AWS account ID"
}
