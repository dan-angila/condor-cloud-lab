locals {
  # Use provided suffix or generate one from timestamp
  bucket_suffix = var.unique_suffix != "" ? var.unique_suffix : formatdate("YYYY-MM-DD-hhmm-ss", timestamp())

  # Common tags for all resources
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "Condor-Cloud-Lab"
  }

  # Service name prefix
  service_name = "danielphilip"

  # Get first available AZ
  availability_zone = data.aws_availability_zones.available.names[0]
}
