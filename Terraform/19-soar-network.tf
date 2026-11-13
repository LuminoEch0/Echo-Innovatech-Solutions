
resource "aws_subnet" "soar_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.40.0/24"
  availability_zone = "eu-central-1a"
  tags = { Name = "private-soar-subnet-1a" }
}

resource "aws_subnet" "soar_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.41.0/24"
  availability_zone = "eu-central-1b"
  tags = { Name = "private-soar-subnet-1b" }
}

resource "aws_route_table_association" "soar_1a" {
  subnet_id      = aws_subnet.soar_1a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "soar_1b" {
  subnet_id      = aws_subnet.soar_1b.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_network_acl" "public_vpn" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public_vpn.id]

  ingress {
    rule_no    = 32766
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 32766
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "public-vpn-nacl-soar-managed" }
}


resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_rt.id]
  tags = { Name = "dynamodb-gateway-endpoint" }
}