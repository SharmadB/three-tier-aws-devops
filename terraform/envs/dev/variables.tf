variable "aws_region" {
  description = "AWS region for the three-tier deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "Expected AWS account ID"
  type        = string
  default     = "342719020675"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "three-tier-aws-devops"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "db_instance_class" {
  description = "RDS instance class for the development database"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial application database name"
  type        = string
  default     = "threetierapp"
}

variable "db_username" {
  description = "Master username for the development database"
  type        = string
  default     = "dbadmin"
}
