#!/bin/bash
# User data script for RHEL 9

# Update system
dnf update -y

# Install and start SSM Agent
#dnf install -y amazon-ssm-agent
dnf install -y https://s3.${aws_region}.amazonaws.com/amazon-ssm-${aws_region}/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install EPEL repository for additional packages
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

# Install EC2 Instance Connect
dnf install -y ec2-instance-connect

# Create a custom banner for identification
cat > /etc/motd << 'EOF'
#############################################
#   RHEL 9 Instance                         #
#   Managed by Terraform                    #
#   SSM Agent: INSTALLED                    #
#   EC2 Instance Connect: INSTALLED         #
#############################################
EOF

# Install additional useful packages
dnf install -y \
    git \
    python3 \
    jq \
    unzip \
    wget \
    curl \
    tar \
    gzip

# Configure Python3 as default
alternatives --set python /usr/bin/python3

echo "User data execution completed successfully at $(date)" >> /var/log/user-data.log
