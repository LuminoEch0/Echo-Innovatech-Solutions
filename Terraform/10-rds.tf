# Random password for RDS — generated at apply time, never written in source code
resource "random_password" "db" {
  length  = 24
  special = false
}

# 1. Group the private database subnets together for RDS
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "app-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_db_1a.id,
    aws_subnet.private_db_1b.id
  ]

  tags = {
    Name = "app-db-subnet-group"
  }
}

# 2. PostgreSQL RDS Instance with Multi-AZ enabled
resource "aws_db_instance" "postgres" {
  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp2"
  db_name                = "appdb"
  engine                 = "postgres"
  engine_version         = "17"
  instance_class         = "db.t3.micro"
  username               = "dbadmin"
  password = random_password.db.result
  # manage_master_user_password  = true   # RDS creates & rotates the secret keys
  # password               = "yourpass!"
  # to get password for the database, you can use the following command in your terminal:
  # aws secretsmanager list-secrets --query "SecretList[*].[Name,ARN]" --output json
  # aws secretsmanager get-secret-value --secret-id "your-rds-secret-name" --query "SecretString" --output text | jq -r '.'
  parameter_group_name   = "default.postgres17"
  
  db_subnet_group_name        = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  
  multi_az                    = true
  publicly_accessible         = false
  skip_final_snapshot         = true

  tags = {
    Name = "main-postgres-db"
  }
}