terraform {
  backend "s3" {
    bucket       = "three-tier-aws-devops-tfstate-342719020675"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
