locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Canonical's official Ubuntu 24.04 LTS x86_64 image. Resolving it at plan time
# avoids hard-coding a region-specific AMI ID while restricting the owner.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
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

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "host" {
  name_prefix = "${local.name}-"
  description = "Restricted access to the self-healing infrastructure lab"
  vpc_id      = aws_vpc.lab.id

  tags = {
    Name = "${local.name}-host"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# The application is reachable only from the operator's supplied CIDR.
resource "aws_vpc_security_group_ingress_rule" "application" {
  security_group_id = aws_security_group.host.id
  description       = "NGINX demo from trusted operator CIDR"
  cidr_ipv4         = var.admin_cidr
  from_port         = 8083
  ip_protocol       = "tcp"
  to_port           = 8083
}

# SSM is preferred. SSH exists only as an explicit opt-in fallback and remains
# restricted to the same operator CIDR; 0.0.0.0/0 is rejected by validation.
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  count = var.enable_ssh ? 1 : 0

  security_group_id = aws_security_group.host.id
  description       = "Optional SSH from trusted operator CIDR"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

# Public egress is needed to install packages, pull container images, reach
# GitHub, and connect the SSM agent. This is a deliberate minimal-lab tradeoff.
resource "aws_vpc_security_group_egress_rule" "internet" {
  security_group_id = aws_security_group.host.id
  description       = "Outbound internet access for bootstrap and SSM"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "host" {
  name               = "${local.name}-host"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${local.name}-host"
  }
}

# This role enables Session Manager access without opening SSH or storing a
# long-lived AWS key on the instance. It does not grant broad admin access.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "host" {
  name = "${local.name}-host"
  role = aws_iam_role.host.name
}

resource "aws_key_pair" "operator" {
  count = var.enable_ssh ? 1 : 0

  key_name   = "${local.name}-operator"
  public_key = var.ssh_public_key

  tags = {
    Name = "${local.name}-operator"
  }
}

resource "aws_instance" "host" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.host.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.host.name
  key_name                    = var.enable_ssh ? aws_key_pair.operator[0].key_name : null

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb

    tags = {
      Name = "${local.name}-root"
    }
  }

  tags = {
    Name = "${local.name}-host"
  }

  depends_on = [aws_iam_role_policy_attachment.ssm]
}
