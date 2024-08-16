// Alchemy Interview 1.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.37"
    }
  }
}

provider "aws" {
  region = "sa-east-1"
  default_tags {
    tags = {
      Environment = "Test"
      Service     = "Project-001"
    }
  }
}

resource "aws_vpc" "vpc-project-001" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "vpc-project-001"
  }
}


resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.vpc-project-001.id

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_subnet" "sn-pub-01-proj-001" {
  vpc_id                  = aws_vpc.vpc-project-001.id
  availability_zone       = "sa-east-1a"
  map_public_ip_on_launch = true
  cidr_block              = "10.0.0.0/24"
  tags = {
    Name = "sn-pub-01-proj-001"
  }
}

resource "aws_subnet" "sn-pub-02-proj-001" {
  vpc_id                  = aws_vpc.vpc-project-001.id
  availability_zone       = "sa-east-1b"
  map_public_ip_on_launch = true
  cidr_block              = "10.0.1.0/24"
  tags = {
    Name = "sn-pub-02-proj-001"
  }
}

resource "aws_subnet" "sn-priv-01-proj-001" {
  vpc_id     = aws_vpc.vpc-project-001.id
  cidr_block = "10.0.2.0/24"
  tags = {
    Name = "sn-priv-01-proj-001"
  }
}

resource "aws_internet_gateway" "igw-project-001" {
  vpc_id = aws_vpc.vpc-project-001.id
  tags = {
    Name = "igw-project-001"
  }
}

resource "aws_route_table" "rtb-pub-project-001" {
  vpc_id = aws_vpc.vpc-project-001.id
  tags = {
    Name = "rtb-pub-project-001"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw-project-001.id
  }
}

resource "aws_eip" "eip_ngw" {

}

resource "aws_nat_gateway" "ngw-project-001" {
  allocation_id = aws_eip.eip_ngw.id
  subnet_id     = aws_subnet.sn-pub-01-proj-001.id
  tags = {
    Name = "ngw-project-001"
  }
  depends_on = [aws_internet_gateway.igw-project-001, aws_eip.eip_ngw]
}

resource "aws_route_table" "rtb-priv-project-001" {
  vpc_id = aws_vpc.vpc-project-001.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw-project-001.id
  }

  tags = {
    Name = "rtb-priv-project-001"
  }
  depends_on = [aws_nat_gateway.ngw-project-001]
}

resource "aws_route_table_association" "sn-pub-01-proj-001" {
  subnet_id      = aws_subnet.sn-pub-01-proj-001.id
  route_table_id = aws_route_table.rtb-pub-project-001.id
}

resource "aws_route_table_association" "sn-pub-02-proj-001" {
  subnet_id      = aws_subnet.sn-pub-02-proj-001.id
  route_table_id = aws_route_table.rtb-pub-project-001.id
}

resource "aws_route_table_association" "sn-priv-01-proj-001" {
  subnet_id      = aws_subnet.sn-priv-01-proj-001.id
  route_table_id = aws_route_table.rtb-priv-project-001.id
}

resource "aws_s3_bucket" "s3-project-001-static" {
  bucket        = "s3-project-001-static"
  force_destroy = true
  tags = {
    Name = "s3-project-001-static"
  }
}

resource "aws_s3_object" "images" {
  depends_on    = [aws_s3_bucket.s3-project-001-static]
  force_destroy = true
  bucket        = "s3-project-001-static"
  key           = "images/"
}

resource "aws_db_subnet_group" "sbg-db-01-project-001-default" {
  name       = "sbg-db-01-project-001-default"
  subnet_ids = [aws_subnet.sn-priv-01-proj-001.id, aws_subnet.sn-pub-01-proj-001.id, aws_subnet.sn-pub-02-proj-001.id]

  tags = {
    Name = "My DB subnet group"
  }
}


resource "aws_db_instance" "db-01-project-001" {
  depends_on = [aws_db_subnet_group.sbg-db-01-project-001-default]

  allocated_storage            = 20
  availability_zone            = aws_subnet.sn-priv-01-proj-001.availability_zone
  db_subnet_group_name         = "sbg-db-01-project-001-default"
  engine                       = "postgres"
  instance_class               = "db.t3.micro"
  username                     = "postgres"
  password                     = "ABCD1234abcd#"
  skip_final_snapshot          = true
  multi_az                     = false
  identifier                   = "db-01-project-001"
  performance_insights_enabled = true
  tags = {
    Name = "db-01-project-001"
  }
}

resource "aws_ssm_parameter" "db-endpoint" {
  depends_on = [aws_db_instance.db-01-project-001]
  type       = "String"
  name       = "db-endpoint"
  value      = element(split(":", aws_db_instance.db-01-project-001.endpoint), 0)
  tags = {
    Name = "db-01-project-001"
  }
}

resource "aws_ec2_instance_connect_endpoint" "ep-subnet-priv-project-001" {
  subnet_id = aws_subnet.sn-priv-01-proj-001.id
  tags = {
    Name = "ep-subnet-priv-project-001"
  }
}

resource "aws_instance" "p-001-ec2-test-01" {
  depends_on = [aws_db_instance.db-01-project-001, aws_ssm_parameter.db-endpoint]

  ami           = "ami-080111c1449900431"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.sn-priv-01-proj-001.id
  key_name      = "std-dev-sa-east-1"
  user_data     = templatefile("user_data.tftpl", { db_endpoint = aws_ssm_parameter.db-endpoint.value })
  tags = {
    Name = "p-001-ec2-test-01"
  }
}

resource "aws_security_group" "web-app-proj-001-sg" {
  name        = "web-app-proj-001-sg"
  description = "Allow ssh and http (8080) inbound traffic and"
  vpc_id      = aws_vpc.vpc-project-001.id

  tags = {
    Name = "web-app-proj-001-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "web-app-proj-001-sg-8080" {
  security_group_id = aws_security_group.web-app-proj-001-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  to_port           = 8080
  from_port         = 8080
}

resource "aws_vpc_security_group_ingress_rule" "web-app-proj-001-sg-ssh" {
  security_group_id = aws_security_group.web-app-proj-001-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  to_port           = 22
  from_port         = 22
}

resource "aws_vpc_security_group_egress_rule" "web-app-proj-001-all" {
  security_group_id = aws_security_group.web-app-proj-001-sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_instance_profile" "role-ec2-s3_profile" {
  name = "role-ec2-s3_profile"
  role = aws_iam_role.role-ec2-s3.name
}

data "aws_iam_policy_document" "role-ec2-s3_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role-ec2-s3" {
  name               = "role-ec2-s3"
  assume_role_policy = data.aws_iam_policy_document.role-ec2-s3_assume_role.json
}

resource "aws_iam_role_policy_attachment" "role-ec2-s3_s3_attach" {
  role       = aws_iam_role.role-ec2-s3.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "role-ec2-s3_ssm_attach" {
  role       = aws_iam_role.role-ec2-s3.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_launch_template" "tmp-simple-web-app" {
  name          = "tmp-simple-web-app"
  image_id      = "ami-0c2752bc89edddb26"
  instance_type = "t3.micro"
  key_name      = "std-dev-sa-east-1"
  iam_instance_profile {
    name = aws_iam_instance_profile.role-ec2-s3_profile.name
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web-app-proj-001-sg.id]
  }
  tags = {
    Name = "tmp-simple-web-app"
  }
}

resource "time_sleep" "wait_90_seconds" {
  create_duration = "90s"
}

resource "aws_lb" "elb-01-project-001" {
  name               = "elb-01-project-001"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.sn-pub-01-proj-001.id, aws_subnet.sn-pub-02-proj-001.id]
}

resource "aws_lb_target_group" "tg-asg-web01-app" {
  name        = "tg-asg-web01-app"
  port        = 8080
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.vpc-project-001.id

  tags = {
    Name = "tg-asg-web01-app"
  }

}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.elb-01-project-001.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-asg-web01-app.arn
  }
}

resource "aws_autoscaling_group" "asg-web01-project-001" {
  depends_on = [aws_db_instance.db-01-project-001, aws_s3_bucket.s3-project-001-static,
  aws_instance.p-001-ec2-test-01, time_sleep.wait_90_seconds]
  vpc_zone_identifier = [aws_subnet.sn-pub-01-proj-001.id, aws_subnet.sn-pub-02-proj-001.id]
  name                = "asg-web01-project-001"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 4
  target_group_arns   = [aws_lb_target_group.tg-asg-web01-app.arn]
  launch_template {
    id      = aws_launch_template.tmp-simple-web-app.id
    version = "$Latest"
  }
}
