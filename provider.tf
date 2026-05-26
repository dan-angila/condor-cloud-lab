terraform {
  required_version = ">= 1.0"
  backend "s3" {
    bucket         = "terraform-bucket-kali"
    key            = "condor-cloud-lab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}
