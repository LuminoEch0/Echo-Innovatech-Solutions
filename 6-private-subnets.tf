resource "aws_subnet" "private_web_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "private-web-subnet-1a"
  }
}

resource "aws_subnet" "private_web_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "private-web-subnet-1b"
  }
}

resource "aws_subnet" "private_monitoring" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.30.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "private-monitoring-subnet-1a"
  }
}