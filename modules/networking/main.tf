resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_security_group" "app_sg" {
  name        = "${var.environment}-app-security-group"
  description = "Managed security group allowing controlled HTTPS traffic"
  vpc_id      = aws_vpc.this.id # Linked directly to internal VPC resource

  tags = {
    Name        = "${var.environment}-app-sg"
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "allow_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr] # Dynamic for both dev (10.0.0.0/16) and prod (10.1.0.0/16)
  security_group_id = aws_security_group.app_sg.id
  description       = "Allow inbound HTTPS from internal network"
}

resource "aws_security_group_rule" "allow_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app_sg.id
  description       = "Allow outbound HTTPS for updates"
}
