resource "aws_db_subnet_group" "postgres" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id

  tags = local.common_tags
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.name_prefix}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  db_name            = var.db_name
  username           = var.db_username
  password           = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false # Cost constraint for MVP — Constitution Principle XI.
  skip_final_snapshot = true

  tags = local.common_tags
}
