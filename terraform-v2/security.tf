locals {
  # Host numbers inside the subnets. Used both for the instances' fixed private
  # IPs and for the Jenkins /32 rule, without making the group depend on the instance.
  hosts = {
    bastion  = 163
    minikube = 237
    git      = 116
    app      = 37
    jenkins  = 160
  }
  jenkins_cidr = "${cidrhost(var.private_subnet_cidr, local.hosts.jenkins)}/32"
}

resource "aws_security_group" "bastion" {
  name        = "Bastion-SG"
  description = "Bastion SSH access" # a description cannot be changed without replacing the group
  vpc_id      = aws_vpc.lab.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Git server, app server and Jenkins server. SSH and HTTP from the bastion and
# from the Minikube host (the runner talks to GitLab on port 80), and
# everything between the members of the group.
resource "aws_security_group" "private" {
  name        = "Private-SG"
  description = "Private servers"
  vpc_id      = aws_vpc.lab.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id, aws_security_group.shopsphere.id]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id, aws_security_group.shopsphere.id]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SSH from the bastion and from the Jenkins server only.
resource "aws_security_group" "shopsphere" {
  name        = "shopsphere-sg"
  description = "ShopSphere minikube"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description     = "SSH from the bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "SSH from the Jenkins server (deploys)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.jenkins_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
