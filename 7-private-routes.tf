resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "priv_web_1a" {
  subnet_id      = aws_subnet.private_web_1a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "priv_web_1b" {
  subnet_id      = aws_subnet.private_web_1b.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "priv_monitoring" {
  subnet_id      = aws_subnet.private_monitoring.id
  route_table_id = aws_route_table.private_rt.id
}