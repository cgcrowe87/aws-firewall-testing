# Pick the first 2 AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az1 = data.aws_availability_zones.available.names[0]
  az2 = data.aws_availability_zones.available.names[1]
}


# -----------------------------------------------------------------------------
# VPC and subnets
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "workload" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.workload_subnet_cidr
  availability_zone       = local.az1
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-workload-${local.az1}"
  }
}

resource "aws_subnet" "firewall_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.firewall_subnet_1_cidr
  availability_zone = local.az1

  tags = {
    Name = "${var.name_prefix}-firewall-${local.az1}"
  }
}

resource "aws_subnet" "firewall_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.firewall_subnet_2_cidr
  availability_zone = local.az2

  tags = {
    Name = "${var.name_prefix}-firewall-${local.az2}"
  }
}

# -----------------------------------------------------------------------------
# Route tables
# -----------------------------------------------------------------------------

# Workload subnet route table:
# send all outbound traffic to the firewall endpoint in AZ1
resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-rt-workload"
  }
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.workload.id
}

# Firewall subnet route tables:
# send traffic from the firewall subnet to the internet gateway
resource "aws_route_table" "firewall_az1" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-rt-firewall-${local.az1}"
  }
}

resource "aws_route_table_association" "firewall_az1" {
  subnet_id      = aws_subnet.firewall_az1.id
  route_table_id = aws_route_table.firewall_az1.id
}

resource "aws_route_table" "firewall_az2" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-rt-firewall-${local.az2}"
  }
}

resource "aws_route_table_association" "firewall_az2" {
  subnet_id      = aws_subnet.firewall_az2.id
  route_table_id = aws_route_table.firewall_az2.id
}

# Internet gateway route table:
# send return traffic for the workload subnet back through the firewall endpoint in AZ1
resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-rt-igw"
  }
}

resource "aws_route_table_association" "igw" {
  gateway_id     = aws_internet_gateway.main.id
  route_table_id = aws_route_table.igw.id
}

# -----------------------------------------------------------------------------
# Network Firewall rules and policy
# -----------------------------------------------------------------------------

resource "aws_networkfirewall_rule_group" "allow_google" {
  name     = "${var.name_prefix}-allow-google"
  capacity = 100
  type     = "STATEFUL"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["TLS_SNI"]
        targets = [
		  ".google.com",
		  ".ssm.${var.aws_region}.amazonaws.com",
		  ".ssmmessages.${var.aws_region}.amazonaws.com",
		  ".ec2messages.${var.aws_region}.amazonaws.com",
                  ".foxnews.com",
                  ".cnn.com",
		]
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "main" {
  name = "${var.name_prefix}-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }

    stateful_default_actions = [
      "aws:drop_established",
      "aws:alert_established"
    ]

    stateful_rule_group_reference {
      priority     = 100
      resource_arn = aws_networkfirewall_rule_group.allow_google.arn
    }
  }
}

resource "aws_networkfirewall_firewall" "main" {
  name                = "${var.name_prefix}-firewall"
  vpc_id              = aws_vpc.main.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn

  subnet_mapping {
    subnet_id = aws_subnet.firewall_az1.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.firewall_az2.id
  }

  delete_protection                 = false
  firewall_policy_change_protection = false
  subnet_change_protection          = false
}

# Read firewall endpoint IDs after creation
data "aws_networkfirewall_firewall" "main" {
  arn = aws_networkfirewall_firewall.main.arn
}

locals {
  firewall_endpoint_az1 = [
    for s in data.aws_networkfirewall_firewall.main.firewall_status[0].sync_states :
    s.attachment[0].endpoint_id
    if s.availability_zone == local.az1
  ][0]
}

# Route workload outbound traffic to the firewall endpoint in AZ1
resource "aws_route" "workload_default" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.firewall_endpoint_az1

  depends_on = [aws_networkfirewall_firewall.main]
}

# Route return traffic from the internet gateway back through the firewall endpoint in AZ1
resource "aws_route" "igw_to_workload" {
  route_table_id         = aws_route_table.igw.id
  destination_cidr_block = var.workload_subnet_cidr
  vpc_endpoint_id        = local.firewall_endpoint_az1

  depends_on = [aws_networkfirewall_firewall.main]
}

# -----------------------------------------------------------------------------
# EC2 instance for testing
# -----------------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2-sg"
  description = "EC2 test instance security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Optional SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all egress - firewall handles filtering"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.name_prefix}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.name_prefix}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_instance" "test" {
  ami                         = "ami-04f2ba315f7ebb999" 
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.workload.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail
              dnf install -y curl
              systemctl enable amazon-ssm-agent
              systemctl restart amazon-ssm-agent
              EOF
  tags = {
    Name = "${var.name_prefix}-test-ec2"
  }
}
