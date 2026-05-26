# ─── KEY PAIR ────────────────────────────────────────────────

# SSH key pair for EC2 access
resource "aws_key_pair" "deployer" {
  key_name   = "${local.service_name}-key"
  public_key = file("${path.home}/.ssh/danielphilip-key.pub")
}

# ─── IAM — BASE RESOURCES ────────────────────────────────────

# Create an IAM user using Terraform
resource "aws_iam_user" "developer" {
  name = "${local.service_name}-developer"
}

# Create an IAM group
resource "aws_iam_group" "devs" {
  name = "${local.service_name}-devs"
}

# ─── S3 — BASE STORAGE ───────────────────────────────────────

# Create an S3 bucket using Terraform
resource "aws_s3_bucket" "my_bucket" {
  bucket = "${local.service_name}-terraform-bucket-${local.bucket_suffix}"
  tags   = merge(local.common_tags, { Name = "${local.service_name}-terraform-bucket" })
}
