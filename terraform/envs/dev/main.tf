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

# NAT instance for outbound internet access from private app subnets.
# Cost-conscious demo design: one NAT instance shared by both app subnets.

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "nat" {
  name        = "${var.project_name}-${var.environment}-nat-sg"
  description = "NAT traffic from private application subnets"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Forward app subnet outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      local.app_subnets.app_a.cidr,
      local.app_subnets.app_b.cidr
    ]
  }

  egress {
    description = "Outbound internet traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat-sg"
  })
}

resource "aws_instance" "nat" {
  ami                         = "ami-03c3da4cfa8e8943a"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public["public_a"].id
  vpc_security_group_ids      = [aws_security_group.nat.id]
  associate_public_ip_address = true
  source_dest_check           = false

  metadata_options {
    http_tokens = "required"
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    dnf install -y iptables

    cat > /usr/local/sbin/configure-nat.sh <<'SCRIPT'
    #!/bin/bash
    set -euo pipefail

    sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-nat.conf

    iptables -t nat -C POSTROUTING -s 10.20.0.0/16 -o ens5 -j MASQUERADE 2>/dev/null || \
      iptables -t nat -A POSTROUTING -s 10.20.0.0/16 -o ens5 -j MASQUERADE

    iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
      iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    iptables -C FORWARD -s 10.20.0.0/16 -j ACCEPT 2>/dev/null || \
      iptables -A FORWARD -s 10.20.0.0/16 -j ACCEPT
    SCRIPT

    chmod 750 /usr/local/sbin/configure-nat.sh

    cat > /etc/systemd/system/nat-iptables.service <<'SERVICE'
    [Unit]
    Description=Configure NAT forwarding and iptables rules
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/sbin/configure-nat.sh
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now nat-iptables.service
  USERDATA

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-nat"
    Tier = "nat"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route" "app_default_via_nat" {
  for_each = aws_route_table.app

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

output "nat_instance_id" {
  description = "ID of the shared NAT instance"
  value       = aws_instance.nat.id
}


# Public Application Load Balancer
resource "aws_lb" "app" {
  name               = "three-tier-dev-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for key in ["public_a", "public_b"] : aws_subnet.public[key].id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-alb"
    Tier = "public"
  })
}

resource "aws_lb_target_group" "app" {
  name     = "three-tier-dev-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# EC2 launch template: the application instances stay in private subnets.
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${var.environment}-app-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.app.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = base64encode(<<-USERDATA
#!/bin/bash
set -euxo pipefail

dnf install -y python3
python3 -m venv /opt/three-tier-venv
/opt/three-tier-venv/bin/pip install --upgrade pip
/opt/three-tier-venv/bin/pip install Flask==3.1.2

mkdir -p /opt/three-tier-app
cat > /opt/three-tier-app/app.py <<'PYTHON'
from flask import Flask, jsonify
import socket

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify({
        "project": "Three-Tier AWS DevOps",
        "message": "Application tier is running!",
        "instance": socket.gethostname()
    })

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYTHON

cat > /etc/systemd/system/three-tier-app.service <<'SERVICE'
[Unit]
Description=Three-Tier Flask Demo Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/three-tier-app
ExecStart=/opt/three-tier-venv/bin/python /opt/three-tier-app/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now three-tier-app
USERDATA
  )

  tag_specifications {
    resource_type = "instance"

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-${var.environment}-app"
      Tier = "application"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-app-lt"
  })
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.project_name}-${var.environment}-app-asg"
  min_size                  = 1
  desired_capacity          = 1
  max_size                  = 2
  vpc_zone_identifier       = [for key in ["app_a", "app_b"] : aws_subnet.app[key].id]
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-app"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

output "alb_dns_name" {
  description = "Public DNS name of the application load balancer"
  value       = aws_lb.app.dns_name
}

output "application_url" {
  description = "HTTP URL for the demo application"
  value       = "http://${aws_lb.app.dns_name}"
}

output "app_asg_name" {
  description = "Application Auto Scaling Group name"
  value       = aws_autoscaling_group.app.name
}
