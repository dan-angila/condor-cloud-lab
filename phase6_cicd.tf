# ============================================================
# Phase 6 — ECR + GitHub Actions OIDC
# Append this block to main.tf
# ============================================================

# -----------------------------------------------------------
# Variables (add these to your variables.tf or top of main.tf)
# -----------------------------------------------------------
variable "github_org" {
  description = "GitHub organisation or username"
  type        = string
  default     = "dan-angila"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "condor-cloud-lab"
}

# -----------------------------------------------------------
# ECR — private container registry
# -----------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "IMMUTABLE" # tags cannot be overwritten

  image_scanning_configuration {
    scan_on_push = true # free Basic scanning on every push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.main.arn
  }

  tags = {
    Name = "${var.project_name}-ecr"
  }
}

# Keep only the 10 most recent tagged images; delete untagged after 1 day
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# -----------------------------------------------------------
# OIDC — trust GitHub Actions; no long-lived keys in GitHub
# -----------------------------------------------------------
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.project_name}-github-oidc"
  }
}

# -----------------------------------------------------------
# IAM role — assumed by GitHub Actions via OIDC
# -----------------------------------------------------------
data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    sid     = "GitHubOIDCTrust"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only the main branch (apply) and PRs (plan) of this repo
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_org}/${var.github_repo}:pull_request"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project_name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# -----------------------------------------------------------
# Least-privilege policy for the pipeline
# Scoped to: ECR push, S3 state read/write, Lambda update,
#            Terraform plan/apply resources in this project
# -----------------------------------------------------------
data "aws_iam_policy_document" "github_actions_permissions" {
  # ECR auth + push to this repo only
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"] # GetAuthorizationToken has no resource constraint
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages"
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  # Terraform remote state bucket
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::terraform-bucket-kali",
      "arn:aws:s3:::terraform-bucket-kali/*"
    ]
  }

  # DynamoDB state locking
  statement {
    sid    = "TerraformLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [
      "arn:aws:dynamodb:us-east-1:886181574003:table/terraform-state-lock"
    ]
  }

  # KMS — decrypt/encrypt state & ECR
  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.main.arn]
  }

  # Lambda deploy (update code from ECR image)
  statement {
    sid    = "LambdaDeploy"
    effect = "Allow"
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:PublishVersion",
      "lambda:UpdateAlias"
    ]
    resources = [
      "arn:aws:lambda:us-east-1:886181574003:function:${var.project_name}-*"
    ]
  }

  # Read-only describes so Terraform plan can diff existing state
  statement {
    sid    = "ReadOnly"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "iam:Get*",
      "iam:List*",
      "s3:GetBucketPolicy",
      "s3:GetEncryptionConfiguration",
      "cloudtrail:GetTrail*",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.project_name}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

# -----------------------------------------------------------
# Outputs
# -----------------------------------------------------------
output "ecr_repository_url" {
  description = "Full ECR URL — use as IMAGE_REGISTRY in the workflow"
  value       = aws_ecr_repository.app.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN — paste into GitHub Actions secrets as AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
