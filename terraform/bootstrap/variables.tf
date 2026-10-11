variable "aws_region" {
  description = "AWS region for Terraform state resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "Expected AWS account ID; prevents deployment to the wrong account"
  type        = string
  default     = "342719020675"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
  default     = "three-tier-aws-devops-tfstate-342719020675"
}
