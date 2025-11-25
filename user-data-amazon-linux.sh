#!/bin/bash
# User data script for Amazon Linux 2

# Update system
yum update -y

# Install and start SSM Agent
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install EC2 Instance Connect
yum install -y ec2-instance-connect

# Create a custom banner for identification
cat > /etc/motd << 'EOF'
#############################################
#   Amazon Linux 2 Instance                 #
#   Managed by Terraform                    #
#   SSM Agent: INSTALLED                    #
#   EC2 Instance Connect: INSTALLED         #
#############################################
EOF

# Install additional useful packages
yum install -y \
    git \
    python3 \
    jq \
    unzip \
    wget \
    curl

echo "User data execution completed successfully at $(date)" >> /var/log/user-data.log
