# Three-Tier AWS DevOps

## Goal
Build and validate a cost-conscious three-tier AWS architecture using Terraform.

## Decisions
- Region: us-east-1
- VPC CIDR: 10.20.0.0/16
- Two Availability Zones
- Public ALB; private application and database tiers
- EC2 Auto Scaling Group; desired 1, minimum 1, maximum 2
- Amazon RDS for MySQL, Single-AZ
- Dedicated S3 Terraform remote state with versioning and locking
- Simple Flask demo application
- Deploy, validate, then destroy temporary billable resources

## Cost and security
- Verify AWS identity, permissions, quotas and pricing before deployment.
- Never commit credentials, secrets, state files or private keys.
- Do not use AWS root identity for routine project provisioning.
- Verify cleanup and remaining billable resources.

## Reference repository
~/cbz-three-tier-infra is reference-only. Never modify or push it.
