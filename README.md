# Three-Tier AWS DevOps Project

A cost-conscious, Infrastructure-as-Code project that provisions and validates a three-tier application architecture on AWS using Terraform.

## Project objective

Build a secure, repeatable AWS environment with public load balancing, a private application tier, and a private managed database tier. Deploy a small Flask application, validate the infrastructure, and destroy temporary resources after testing to control ongoing costs.

## Architecture

```text
                         Internet
                            |
                       HTTP :80
                            |
                 Application Load Balancer
                    (Public subnets)
                     /             \
              Availability Zone A  Availability Zone B
                     |
              Private application subnets
                     |
            EC2 Auto Scaling Group
              Flask application
                 Port 5000
                     |
              MySQL :3306
                     |
                Amazon RDS
              Private DB subnets

Outbound internet access for app subnets:
Private app route tables -> NAT instance -> Internet Gateway

Terraform state:
S3 bucket with versioning, encryption, public-access blocking,
and native S3 state locking.
```

The load balancer spans two Availability Zones. The Auto Scaling Group is configured with minimum/desired capacity 1 and maximum capacity 2. The database is Single-AZ to reduce demo costs. A single NAT instance is shared by both application subnets; it is a cost-conscious choice, not a highly available production design.

## Technology stack

- AWS VPC, subnets, route tables, Internet Gateway, security groups
- Application Load Balancer and target group health checks
- EC2 Launch Template and Auto Scaling Group
- NAT instance for private-subnet outbound access
- Amazon RDS for MySQL
- Amazon S3 remote Terraform state and native state locking
- Terraform and AWS CLI
- Python Flask sample application

## Security design

- The ALB accepts HTTP traffic on port 80.
- The application security group allows port 5000 only from the ALB security group.
- The database security group allows MySQL port 3306 only from the application security group.
- The RDS database is not publicly accessible.
- The DB subnets have no default internet route.
- The application subnets use the NAT instance for outbound connectivity.
- Terraform state storage uses S3 versioning, encryption, and public-access blocking.
- AWS credentials, Terraform state, plan files, and private keys must never be committed.

## Repository layout

```text
.
├── app/
│   ├── app.py
│   └── requirements.txt
├── terraform/
│   ├── bootstrap/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   └── variables.tf
│   └── envs/
│       └── dev/
│           ├── backend.tf
│           ├── main.tf
│           ├── nat.tf
│           ├── variables.tf
│           └── versions.tf
├── PROJECT_NOTES.md
└── README.md
```

## Prerequisites

- AWS CLI v2
- Terraform compatible with the version constraint in the configuration
- Git
- An AWS account with suitable permissions and available service quotas
- An authenticated AWS CLI session

This project was tested in Ubuntu under WSL2, using AWS region `us-east-1`.

## Configure AWS CLI

Use the named profile configured for this project:

```bash
export AWS_PROFILE=three-tier-devops
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
```

If the session has expired, authenticate again using the approved AWS CLI login flow. Never commit credentials or paste secret values into project files.

## Deployment workflow

Review the Terraform files and current AWS account before provisioning.

### 1. Bootstrap remote state

The bootstrap configuration creates the S3 bucket used for Terraform state. It has already been created for this deployment.

For a fresh environment, inspect `terraform/bootstrap/backend.tf` and `terraform/bootstrap/main.tf` carefully. Bootstrapping a backend has a special ordering requirement: the bucket must exist before Terraform can initialize against that bucket. Follow the configured bootstrap and state-migration process rather than blindly applying the bootstrap configuration.

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap validate
terraform -chdir=terraform/bootstrap plan
```

Review the plan before applying. Do not recreate or delete the existing state bucket casually.

### 2. Initialize the development environment

```bash
terraform -chdir=terraform/envs/dev init
terraform -chdir=terraform/envs/dev validate
terraform -chdir=terraform/envs/dev plan
```

Review every proposed change before applying.

### 3. Deploy

```bash
terraform -chdir=terraform/envs/dev apply
```

Approve only after checking the plan and confirming the expected AWS account and region.

### 4. Inspect outputs

```bash
terraform -chdir=terraform/envs/dev output
```

Use the `application_url` output to access the demo application.

### 5. Validate the application and database

```bash
curl -i "$(terraform -chdir=terraform/envs/dev output -raw application_url)/health"

aws rds describe-db-instances \
  --db-instance-identifier three-tier-aws-devops-dev-mysql \
  --query 'DBInstances[0].[DBInstanceStatus,Engine,DBInstanceClass,PubliclyAccessible,MultiAZ]' \
  --output table
```

The `/health` endpoint was validated with HTTP 200. RDS was validated as available, MySQL 8.0.46, `db.t3.micro`, not publicly accessible, and Single-AZ.

**Application scope:** The Flask sample application currently demonstrates application delivery and health checks. It does not yet execute database queries against RDS. The database tier is provisioned separately; do not describe the demo as a fully database-integrated application.

### 6. Check for configuration drift

```bash
terraform -chdir=terraform/envs/dev plan
```

After successful deployment and no configuration changes, the expected result is no changes.

## Cost management and cleanup

AWS resources can incur charges even while idle. Credits are not a guaranteed spending cap.

For this project, potentially billable resources include the ALB, EC2 instances, public IPv4 addresses, RDS, NAT instance, data transfer, S3 storage, and the managed database secret.

After testing and capturing evidence, destroy the development stack:

```bash
terraform -chdir=terraform/envs/dev destroy
```

Review the destroy plan and confirm only after understanding what will be deleted.

Then verify the database is gone:

```bash
aws rds describe-db-instances \
  --query "DBInstances[?DBInstanceIdentifier=='three-tier-aws-devops-dev-mysql'].[DBInstanceIdentifier,DBInstanceStatus]" \
  --output table
```

Also inspect EC2 instances, load balancers, NAT resources, public IP allocations, volumes, and snapshots for leftovers. Do not delete the S3 state bucket as part of routine development cleanup.

## Rebuilding later

1. Clone this repository.
2. Authenticate to the intended AWS account.
3. Confirm the existing remote-state bucket and backend configuration.
4. Initialize Terraform in `terraform/envs/dev`.
5. Review the plan and current AWS costs.
6. Apply, validate, capture evidence, and destroy the development stack when finished.

If the remote state bucket or its state object is missing, stop and recover the backend deliberately before applying infrastructure. Do not create a second stack blindly.

## Design trade-offs and limitations

- A single NAT instance costs less than a NAT Gateway in this demo, but it is a single point of failure and requires operating-system maintenance.
- The ASG desired capacity is one, so the application is not continuously redundant.
- RDS is Single-AZ and configured for demo lifecycle management rather than production data retention.
- HTTP is used for this sample; HTTPS and a custom domain are not configured.
- Flask health checks and a separate RDS deployment are demonstrated; application-to-database query integration is not implemented.
- The AMI used by the application launch template is pinned for repeatable plans. Review and update it deliberately when refreshing the operating system image.

## Project status

The AWS infrastructure was provisioned successfully and validated. The ALB health endpoint returned HTTP 200, the RDS instance reached `available`, and Terraform reported no configuration drift after deployment.

The development resources are intended to be destroyed after final evidence capture. Check the live AWS account before claiming that cleanup is complete.

## Author

Sharmad Bhandari
