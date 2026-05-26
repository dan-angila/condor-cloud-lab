# Create an S3 bucket using Terraform
resource "aws_s3_bucket" "my_bucket" {
  bucket = "terraform-bucket-kali"
}

# Create an IAM user using Terraform
resource "aws_iam_user" "developer" {
  name = "terraform-developer"
}

# Create an IAM group
resource "aws_iam_group" "devs" {
  name = "terraform-devs"
}

# ─── NETWORKING LAYER ────────────────────────────────────────

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "psycho-vpc" }
}

# Public Subnet (for load balancers, bastion hosts)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "psycho-public" }
}

# Private Subnet (for app servers, databases)
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "psycho-private" }
}

# Internet Gateway (gives public subnet internet access)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "psycho-igw" }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "psycho-public-rt" }
}

# Associate public subnet with public route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group — allows HTTP and SSH inbound
resource "aws_security_group" "web" {
  name   = "danielphilip-web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["102.219.210.194/32"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["102.219.210.194/32"]
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
  tags = { Name = "psycho-web-sg" }
}

# ─── COMPUTE LAYER ───────────────────────────────────────────

# IAM Role for EC2 (lets the instance talk to AWS services)
resource "aws_iam_role" "ec2_role" {
  name = "danielphilip-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach S3 read access to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_s3" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Instance profile (wraps the role so EC2 can use it)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "danielphilip-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance — sits in public subnet, uses web security group
resource "aws_instance" "web" {
  ami                         = "ami-0d5e7e27578d32e47"  # LocalStack accepts any AMI ID
  instance_type               = "t3.micro"
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
    echo "<h1>Daniel Philip Cloud Lab — Web Server</h1>" > /var/www/html/index.html
  USERDATA

  tags = { Name = "danielphilip-web-01" }
}

# Elastic IP — gives the instance a static public IP
resource "aws_eip" "web" {
  instance = aws_instance.web.id
  domain   = "vpc"
  tags     = { Name = "danielphilip-eip" }
}

# ─── APP LAYER ───────────────────────────────────────────────

# DynamoDB — users table
resource "aws_dynamodb_table" "users" {
  name         = "danielphilip-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  tags = { Name = "danielphilip-users" }
}

# SQS Queue — job processing
resource "aws_sqs_queue" "jobs" {
  name                      = "danielphilip-jobs"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400
  tags                      = { Name = "danielphilip-jobs" }
}

# SQS Dead Letter Queue — failed jobs land here
resource "aws_sqs_queue" "jobs_dlq" {
  name = "danielphilip-jobs-dlq"
  tags = { Name = "danielphilip-jobs-dlq" }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "danielphilip-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Lambda policy — DynamoDB + SQS + logs
resource "aws_iam_role_policy" "lambda_policy" {
  name = "danielphilip-lambda-policy"
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

# Lambda function code (inline zip)
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/danielphilip-lambda.zip"
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
        return respond(200, {'status': 'ok', 'lab': 'Daniel Philip Cloud Lab'})

    if method == 'POST' and path == '/users':
        body = json.loads(event.get('body', '{}'))
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
        table = dynamodb.Table(TABLE)
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

# Lambda function
resource "aws_lambda_function" "api" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "danielphilip-api"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      USERS_TABLE = aws_dynamodb_table.users.name
      JOBS_QUEUE       = aws_sqs_queue.jobs.url
    }
  }

  tags = { Name = "danielphilip-api" }
}

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "danielphilip-api-gw"
  description = "Daniel Philip Cloud Lab API"
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
  stage_name  = "prod"
  depends_on  = [aws_api_gateway_integration.lambda]
}

# Lambda permission — allow API Gateway to invoke it
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ─── OBSERVABILITY ───────────────────────────────────────────

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/danielphilip-api"
  retention_in_days = 7
  tags              = { Name = "danielphilip-lambda-logs" }
}

# ─── SNS NOTIFICATIONS ───────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "danielphilip-alerts"
  tags = { Name = "danielphilip-alerts" }
}

resource "aws_sns_topic" "deployments" {
  name = "danielphilip-deployments"
  tags = { Name = "danielphilip-deployments" }
}

# Wire SQS to SNS — alerts fan out to the jobs queue
resource "aws_sns_topic_subscription" "alerts_to_sqs" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.jobs.arn
}

# ─── S3 APP STORAGE ──────────────────────────────────────────

resource "aws_s3_bucket" "app_storage" {
  bucket = "danielphilip-app-storage"
  tags   = { Name = "danielphilip-app-storage" }
}

resource "aws_s3_bucket_versioning" "app_storage" {
  bucket = aws_s3_bucket.app_storage.id
  versioning_configuration { status = "Enabled" }
}

# Versioning on the original bucket
resource "aws_s3_bucket_versioning" "main_bucket" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration { status = "Enabled" }
}

# ─── IAM — ATTACH POLICY TO GROUP ───────────────────────────

resource "aws_iam_policy" "dev_policy" {
  name = "danielphilip-dev-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject","s3:PutObject","s3:ListBucket"]
        Resource = ["${aws_s3_bucket.app_storage.arn}","${aws_s3_bucket.app_storage.arn}/*"]
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

# ─── OUTPUTS ─────────────────────────────────────────────────

output "api_url" {
  value       = "https://${aws_api_gateway_rest_api.main.id}.execute-api.us-east-1.amazonaws.com/prod"
  description = "Daniel Philip API Gateway URL"
}

output "lambda_name" {
  value = aws_lambda_function.api.function_name
}

output "dynamodb_table" {
  value = aws_dynamodb_table.users.name
}

output "jobs_queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "app_storage_bucket" {
  value = aws_s3_bucket.app_storage.bucket
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "ec2_instance_id" {
  value = aws_instance.web.id
}

output "ec2_public_ip" {
  value = aws_eip.web.public_ip
}

output "vpc_id" {
  value = aws_vpc.main.id
}

resource "aws_key_pair" "deployer" {
  key_name   = "danielphilip-key"
  public_key = file("~/.ssh/danielphilip-key.pub")
}
