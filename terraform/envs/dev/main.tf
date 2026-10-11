data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  public_subnets = {
    public_a = {
      cidr = "10.20.1.0/24"
      az   = local.azs[0]
    }
    public_b = {
      cidr = "10.20.2.0/24"
      az   = local.azs[1]
    }
  }

  app_subnets = {
    app_a = {
      cidr = "10.20.11.0/24"
      az   = local.azs[0]
    }
    app_b = {
      cidr = "10.20.12.0/24"
      az   = local.azs[1]
    }
  }

  db_subnets = {
    db_a = {
      cidr = "10.20.21.0/24"
      az   = local.azs[0]
    }
    db_b = {
      cidr = "10.20.22.0/24"
      az   = local.azs[1]
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "app" {
  for_each = local.app_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${each.key}"
    Tier = "application"
  })
}

resource "aws_subnet" "db" {
  for_each = local.db_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${each.key}"
    Tier = "database"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "app" {
  for_each = aws_subnet.app

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${each.key}-rt"
  })
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

resource "aws_route_table" "db" {
  for_each = aws_subnet.db

  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${each.key}-rt"
  })
}

resource "aws_route_table_association" "db" {
  for_each = aws_subnet.db

  subnet_id      = each.value.id
  route_table_id = aws_route_table.db[each.key].id
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Public HTTP access to the application load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward traffic to application tier"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  })
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  description = "Application traffic allowed only from the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Flask application traffic from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound required for application operations"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-app-sg"
  })
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "MySQL access allowed only from the application tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from application tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-sg"
  })
}

output "vpc_id" {
  description = "ID of the project VPC"
  value       = aws_vpc.main.id
}

output "availability_zones" {
  description = "Availability zones used by the project"
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  value       = { for key, subnet in aws_subnet.public : key => subnet.id }
}

output "app_subnet_ids" {
  description = "Private application subnet IDs"
  value       = { for key, subnet in aws_subnet.app : key => subnet.id }
}

output "db_subnet_ids" {
  description = "Private database subnet IDs"
  value       = { for key, subnet in aws_subnet.db : key => subnet.id }
}
