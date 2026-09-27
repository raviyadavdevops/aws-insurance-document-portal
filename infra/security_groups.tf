# Four distinct security groups per spec.md SEC-004/SEC-005: ALB, EC2, Lambda, RDS.
# EC2 has NO ingress/egress rule granting it access to rds_sg — enforced by omission below.

resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  vpc_id      = aws_vpc.main.id
  description = "Allows inbound HTTP from the internet; forwards to EC2."

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
}

resource "aws_security_group" "ec2" {
  name_prefix = "${local.name_prefix}-ec2-"
  vpc_id      = aws_vpc.main.id
  description = "Allows inbound app traffic only from the ALB. No route to RDS."

  ingress {
    description     = "App traffic from ALB only"
    from_port        = 8000
    to_port          = 8000
    protocol         = "tcp"
    security_groups  = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound to S3 (via Gateway Endpoint) and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ec2-sg" })
}

resource "aws_security_group" "lambda" {
  name_prefix = "${local.name_prefix}-lambda-"
  vpc_id      = aws_vpc.main.id
  description = "No ingress. Egress to RDS, S3, and CloudWatch Logs."

  egress {
    description = "Outbound to RDS, S3 endpoint, and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-lambda-sg" })
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  vpc_id      = aws_vpc.main.id
  description = "Allows inbound PostgreSQL only from the Lambda security group."

  ingress {
    description     = "PostgreSQL from Lambda only"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-rds-sg" })
}
