terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get the current AWS region
data "aws_region" "current" {}

# Get the current AWS caller identity
data "aws_caller_identity" "current" {}

# Create new VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "ec2-instance-connect-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ec2-instance-connect-igw"
  }
}

# Create public subnet
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# Create route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create security group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-instance-connect-sg"
  description = "Security group for EC2 Instance Connect and SSM"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress - allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-instance-connect-sg"
  }
}

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "ec2-instance-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "ec2-instance-connect-role"
  }
}

# IAM policy for EC2 Instance Connect
resource "aws_iam_policy" "ec2_instance_connect" {
  name        = "EC2InstanceConnectPolicy"
  description = "Policy for EC2 Instance Connect access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2-instance-connect:SendSSHPublicKey",
          "ec2-instance-connect:SendSerialConsoleSSHPublicKey"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "ec2:osuser" = ["ec2-user", "root"]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for SSM Session Manager
resource "aws_iam_policy" "ssm_managed_instance" {
  name        = "SSMManagedInstancePolicy"
  description = "Policy for SSM Session Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "s3:GetEncryptionConfiguration"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach policies to IAM role
resource "aws_iam_role_policy_attachment" "ec2_instance_connect" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_instance_connect.arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ssm_managed_instance.arn
}

resource "aws_iam_role_policy_attachment" "amazon_ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-connect-profile"
  role = aws_iam_role.ec2_role.name
}

# User data scripts using templatefile function
locals {
  user_data_amazon_linux = templatefile("${path.module}/user-data-amazon-linux.sh", {})
  user_data_rhel9        = templatefile("${path.module}/user-data-rhel9.sh", {
    aws_region = var.aws_region
  })
}

# Find latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Find latest RHEL 9 AMI
data "aws_ami" "rhel_9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat's account ID

  filter {
    name   = "name"
    values = ["RHEL-9.2.*_HVM-*-x86_64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Create Amazon Linux 2 EC2 instance
resource "aws_instance" "amazon_linux" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  user_data              = local.user_data_amazon_linux
  subnet_id              = aws_subnet.public[0].id  # Use first public subnet

  tags = {
    Name = "amazon-linux-ec2-instance"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }
}

# Create RHEL 9 EC2 instance
resource "aws_instance" "rhel_9" {
  ami                    = data.aws_ami.rhel_9.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name
  user_data              = local.user_data_rhel9
  subnet_id              = aws_subnet.public[1].id  # Use second public subnet

  tags = {
    Name = "rhel9-ec2-instance"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }
}

# Output the instance details
output "amazon_linux_instance" {
  value = {
    instance_id   = aws_instance.amazon_linux.id
    public_ip     = aws_instance.amazon_linux.public_ip
    private_ip    = aws_instance.amazon_linux.private_ip
    instance_type = aws_instance.amazon_linux.instance_type
    az            = aws_instance.amazon_linux.availability_zone
    subnet_id     = aws_instance.amazon_linux.subnet_id
  }
}

output "rhel9_instance" {
  value = {
    instance_id   = aws_instance.rhel_9.id
    public_ip     = aws_instance.rhel_9.public_ip
    private_ip    = aws_instance.rhel_9.private_ip
    instance_type = aws_instance.rhel_9.instance_type
    az            = aws_instance.rhel_9.availability_zone
    subnet_id     = aws_instance.rhel_9.subnet_id
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.main.id
}
