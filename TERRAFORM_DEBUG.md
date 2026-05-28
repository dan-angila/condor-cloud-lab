# Terraform Initialization Debug Report

## Issue Summary
The Terraform workflow is failing at the `terraform init` step with the following errors:

### Error 1: State Digest Mismatch
```
Error: Inconsistent/Corrupted Remote State

The remote state stored in S3 has a different Digest than the local state.
```

### Error 2: DynamoDB State Lock Failure
```
Error acquiring the state lock - ConditionalCheckFailedException: The conditional request failed
Lock ID: <stale-lock-id>
```

---

## Root Causes Identified

### 1. **Stale DynamoDB Lock Entry**
- A previous Terraform run left a lock in the DynamoDB table
- The lock entry has an invalid digest that doesn't match the current state file
- Manual cleanup required

### 2. **S3 State File Corruption/Mismatch**
- The Terraform state file in S3 (`terraform-bucket-kali`) may be corrupted
- Backend config mismatch between local and remote

### 3. **Missing SSH_PUBLIC_KEY Secret**
- The `terraform plan` step requires `SSH_PUBLIC_KEY` secret
- If not set, it fails with validation errors

### 4. **Account ID Hardcoded in IAM Policies**
- `main.tf` line 461 and `phase6_cicd.tf` line 189 have hardcoded account ID `886181574003`
- This must match the AWS account running the pipeline

---

## Solutions

### Solution 1: Clear Stale DynamoDB Lock (Manual)

Run in AWS CLI:
```bash
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"condor-cloud-lab/terraform.tfstate"}}' \
  --region us-east-1
```

### Solution 2: Verify Backend Configuration

In `provider.tf`, ensure these match exactly:
```hcl
backend "s3" {
  bucket         = "terraform-bucket-kali"
  key            = "condor-cloud-lab/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "terraform-state-lock"
  encrypt        = true
}
```

### Solution 3: Add GitHub Secrets

```bash
AWS_ROLE_ARN=arn:aws:iam::886181574003:role/danielphilip-github-actions
SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
```

### Solution 4: Replace Hardcoded Account ID

Search for `886181574003` and replace with dynamic value:
```hcl
account_id = data.aws_caller_identity.current.account_id
```

---

## Updated Workflow Steps

The Terraform initialization process should follow:

1. **Terraform Init** - Initialize backend
2. **Terraform Validate** - Check syntax
3. **Terraform Plan** - Generate execution plan
4. **Terraform Apply** - Deploy infrastructure

Each step must succeed before proceeding to the next.

---

## Quick Debug Commands

```bash
# Check S3 state file
aws s3 cp s3://terraform-bucket-kali/condor-cloud-lab/terraform.tfstate - | jq .

# Check DynamoDB locks
aws dynamodb scan --table-name terraform-state-lock --region us-east-1

# Force unlock (use with caution!)
terraform force-unlock <LOCK_ID>
```
