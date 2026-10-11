# Deployment and Cleanup Runbook

## Environment

- AWS region: us-east-1
- AWS CLI profile: three-tier-devops
- Terraform root: terraform/envs/dev
- Remote state bucket: three-tier-aws-devops-tfstate-342719020675

## Before any operation

```bash
cd ~/three-tier-aws-devops
export AWS_PROFILE=three-tier-devops
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
terraform -chdir=terraform/envs/dev validate
terraform -chdir=terraform/envs/dev plan
```

Verify the AWS account and inspect all proposed changes.

## Deploy or rebuild

```bash
terraform -chdir=terraform/envs/dev init
terraform -chdir=terraform/envs/dev validate
terraform -chdir=terraform/envs/dev plan
terraform -chdir=terraform/envs/dev apply
terraform -chdir=terraform/envs/dev output
```

## Smoke tests

```bash
APP_URL="$(terraform -chdir=terraform/envs/dev output -raw application_url)"
curl -i --max-time 10 "$APP_URL/health"
curl -i --max-time 10 "$APP_URL/"
```

Check RDS status:

```bash
aws rds describe-db-instances \
  --db-instance-identifier three-tier-aws-devops-dev-mysql \
  --query 'DBInstances[0].[DBInstanceStatus,Engine,DBInstanceClass,PubliclyAccessible,MultiAZ,Endpoint.Address]' \
  --output table
```

## Destroy the development stack

Capture final evidence and push the code before destroying resources.

```bash
terraform -chdir=terraform/envs/dev plan -destroy
terraform -chdir=terraform/envs/dev destroy
```

Review the proposed deletions before confirming.

## Post-cleanup verification

Check RDS:

```bash
aws rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='three-tier-aws-devops-dev-mysql'].[DBInstanceIdentifier,DBInstanceStatus]" \
  --output table
```

Check EC2 instances belonging to this project:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=three-tier-aws-devops" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,PublicIpAddress]' \
  --output table
```

Check load balancers:

```bash
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'three-tier-dev')].[LoadBalancerName,State.Code,DNSName]" \
  --output table
```

Inspect Elastic IP allocations, EBS volumes, snapshots, and other leftover resources in the AWS Console or CLI. Investigate anything still present before considering cleanup complete.

## Preserve

- GitHub repository and Git history
- Terraform source and lock files
- Bootstrap S3 bucket, versioning, encryption, and remote state
- Project documentation and screenshots

Do not manually delete Terraform state objects or the state bucket during routine cleanup.
