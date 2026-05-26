
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/condor-lambda.zip"
  source {
    content  = <<PYTHON
import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs      = boto3.client('sqs')

TABLE = os.environ.get('USERS_TABLE', 'danielphilip-users')
QUEUE = os.environ.get('JOBS_QUEUE',  'danielphilip-jobs')

def handler(event, context):
    method = event.get('httpMethod', 'GET')
    path   = event.get('path', '/')
    if method == 'GET' and path == '/health':
        return respond(200, {'status': 'ok', 'lab': 'Condor Cloud Lab'})
    if method == 'POST' and path == '/users':
        body  = json.loads(event.get('body', '{}'))
        table = dynamodb.Table(TABLE)
        item  = {
            'userId':    body.get('userId', f"user-{datetime.utcnow().timestamp()}"),
            'name':      body.get('name', 'Unknown'),
            'email':     body.get('email', ''),
            'createdAt': datetime.utcnow().isoformat()
        }
        table.put_item(Item=item)
        return respond(201, {'message': 'User created', 'user': item})
    if method == 'GET' and path == '/users':
        table  = dynamodb.Table(TABLE)
        result = table.scan()
        return respond(200, {'users': result.get('Items', [])})
    return respond(404, {'error': 'Route not found'})

def respond(status, body):
    return {
        'statusCode': status,
        'headers':    {'Content-Type': 'application/json'},
        'body':       json.dumps(body)
    }
PYTHON
    filename = "handler.py"
  }
}

# ─── KEY PAIR ────────────────────────────────────────────────
resource "aws_key_pair" "deployer" {
  key_name   = "${local.service_name}-key"
  public_key = var.ssh_public_key
  tags       = merge(local.common_tags, { Name = "${local.service_name}-key" })
}

# ─── IAM — BASE ──────────────────────────────────────────────
resource "aws_iam_user" "developer" {
  name = "${local.service_name}-developer"
  tags = local.common_tags
}

resource "aws_iam_group" "devs" {
  name = "${local.service_name}-devs"
}

resource "aws_iam_policy" "dev_policy" {
  name = "${local.service_name}-dev-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject","s3:PutObject","s3:ListBucket"]
        Resource = [aws_s3_bucket.app_storage.arn,"${aws_s3_bucket.app_storage.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:Scan"]
        Resource = aws_dynamodb_table.users.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage","sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.jobs.arn
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "devs_policy" {
  group      = aws_iam_group.devs.name
  policy_arn = aws_iam_policy.dev_policy.arn
}

# ─── S3 ──────────────────────────────────────────────────────
resource "aws_s3_bucket" "my_bucket" {
  bucket = "${local.service_name}-terraform-bucket"
  tags   = merge(local.common_tags, { Name = "${local.service_name}-terraform-bucket" })
}

resource "aws_s3_bucket" "app_storage" {
  bucket = "${local.service_name}-app-storage"
  tags   = merge(local.common_tags, { Name = "${local.service_name}-app-storage" })
}

resource "aws_s3_bucket_versioning" "app_storage" {
  bucket = aws_s3_bucket.app_storage.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "main_bucket" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "app_storage" {
  bucket                  = aws_s3_bucket.app_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "main_bucket" {
  bucket                  = aws_s3_bucket.my_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── NETWORKING ──────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${local.service_name}-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.service_name}-public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_cidr
  availability_zone = local.availability_zone
  tags              = merge(local.common_tags, { Name = "${local.service_name}-private" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.service_name}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, { Name = "${local.service_name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name   = "${local.service_name}-web-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_access_cidr]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.ssh_access_cidr]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${local.service_name}-web-sg" })
}

# ─── COMPUTE ─────────────────────────────────────────────────
resource "aws_iam_role" "ec2_role" {
  name = "${local.service_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.service_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "web" {
  ami                         = var.ec2_ami
  instance_type               = var.ec2_instance_type
  key_name                    = aws_key_pair.deployer.key_name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true
  user_data = <<-USERDATA
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Condor Cloud Lab</h1>" > /var/www/html/index.html
  USERDATA
  tags = merge(local.common_tags, { Name = "${local.service_name}-web-01" })
}

resource "aws_eip" "web" {
  instance = aws_instance.web.id
  domain   = "vpc"
  tags     = merge(local.common_tags, { Name = "${local.service_name}-eip" })
}

resource "aws_ec2_instance_metadata_defaults" "main" {
  http_tokens = "required"
}

# ─── APP LAYER ───────────────────────────────────────────────
resource "aws_dynamodb_table" "users" {
  name         = "${local.service_name}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  attribute {
    name = "userId"
    type = "S"
  }
  tags = merge(local.common_tags, { Name = "${local.service_name}-users" })
}

resource "aws_sqs_queue" "jobs" {
  name                      = "${local.service_name}-jobs"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400
  tags                      = merge(local.common_tags, { Name = "${local.service_name}-jobs" })
}

resource "aws_sqs_queue" "jobs_dlq" {
  name = "${local.service_name}-jobs-dlq"
  tags = merge(local.common_tags, { Name = "${local.service_name}-jobs-dlq" })
}

resource "aws_sns_topic" "alerts" {
  name = "${local.service_name}-alerts"
  tags = merge(local.common_tags, { Name = "${local.service_name}-alerts" })
}

resource "aws_sns_topic" "deployments" {
  name = "${local.service_name}-deployments"
  tags = merge(local.common_tags, { Name = "${local.service_name}-deployments" })
}

resource "aws_sns_topic_subscription" "alerts_to_sqs" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.jobs.arn
}

resource "aws_iam_role" "lambda_role" {
  name = "${local.service_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.service_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:Scan","dynamodb:UpdateItem","dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.users.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage","sqs:ReceiveMessage","sqs:DeleteMessage"]
        Resource = aws_sqs_queue.jobs.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "api" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.service_name}-api"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = var.lambda_runtime
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  environment {
    variables = {
      USERS_TABLE = aws_dynamodb_table.users.name
      JOBS_QUEUE  = aws_sqs_queue.jobs.url
    }
  }
  tags = merge(local.common_tags, { Name = "${local.service_name}-api" })
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.service_name}-api-gw"
  description = "Condor Cloud Lab API"
  tags        = local.common_tags
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  depends_on  = [aws_api_gateway_integration.lambda]
  lifecycle   { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
  tags          = local.common_tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ─── OBSERVABILITY ───────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.service_name}-api"
  retention_in_days = var.cloudwatch_retention_days
  tags              = merge(local.common_tags, { Name = "${local.service_name}-lambda-logs" })
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.service_name}-flow-logs"
  retention_in_days = var.cloudwatch_retention_days
  tags              = merge(local.common_tags, { Name = "${local.service_name}-vpc-flow-logs" })
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${local.service_name}-vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${local.service_name}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogGroups","logs:DescribeLogStreams"]
      Resource = "*"
    }]
  })
}

# ─── CLOUDTRAIL ──────────────────────────────────────────────
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.service_name}-cloudtrail-logs"
  force_destroy = true
  tags          = merge(local.common_tags, { Name = "${local.service_name}-cloudtrail-logs" })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/886181574003/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${local.service_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.main.arn
  tags                          = merge(local.common_tags, { Name = "${local.service_name}-trail" })
  depends_on                    = [aws_s3_bucket_policy.cloudtrail, aws_kms_key_policy.main]
}
