resource "aws_security_group" "app_sg" {
  name        = "${var.environment}-app-security-group"
  description = "Managed security group allowing controlled HTTPS traffic"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.environment}-app=-sg"
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "allow_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]
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
