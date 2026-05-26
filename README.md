# Daniel Philip Cloud Lab

Production cloud infrastructure on AWS — VPC, EC2, Lambda, DynamoDB, API Gateway, SNS, SQS

## Live API
`https://zpx1mlmjde.execute-api.us-east-1.amazonaws.com/prod`

## Architecture
- **Networking**: VPC, public/private subnets, IGW, security groups
- **Compute**: EC2 t3.micro, Elastic IP
- **Serverless**: Lambda (python3.11), API Gateway
- **Storage**: DynamoDB, S3 (versioned)
- **Messaging**: SQS, SNS fanout
- **Observability**: CloudWatch Logs
- **IaC**: Terraform (38 resources)

## CI/CD
Automated deployment via GitHub Actions — terraform plan + apply on every push to main.
