locals {
  instances = {
    bastion = {
      name      = "bastion"
      type      = "t3.micro"
      subnet    = aws_subnet.public.id
      cidr      = var.public_subnet_cidr
      sg        = aws_security_group.bastion.id
      volume_gb = 8
      public_ip = true
      profile   = null
    }
    minikube = {
      name      = "shopsphere-minikube"
      type      = "m7i-flex.large"
      subnet    = aws_subnet.public.id
      cidr      = var.public_subnet_cidr
      sg        = aws_security_group.shopsphere.id
      volume_gb = 40
      public_ip = true
      profile   = null
    }
    git = {
      name      = "git-server"
      type      = "c7i-flex.large"
      subnet    = aws_subnet.private.id
      cidr      = var.private_subnet_cidr
      sg        = aws_security_group.private.id
      volume_gb = 30
      public_ip = false
      profile   = null
    }
    app = {
      name      = "app server"
      type      = "t3.micro"
      subnet    = aws_subnet.private.id
      cidr      = var.private_subnet_cidr
      sg        = aws_security_group.private.id
      volume_gb = 20
      public_ip = false
      profile   = null
    }
    jenkins = {
      name      = "Jenkins-server"
      type      = "t3.small"
      subnet    = aws_subnet.private.id
      cidr      = var.private_subnet_cidr
      sg        = aws_security_group.private.id
      volume_gb = 16
      public_ip = false
      profile   = aws_iam_instance_profile.jenkins.name
    }
  }
}

resource "aws_instance" "lab" {
  for_each = local.instances

  ami                         = var.ami_id
  instance_type               = each.value.type
  subnet_id                   = each.value.subnet
  private_ip                  = cidrhost(each.value.cidr, local.hosts[each.key])
  key_name                    = var.key_name
  vpc_security_group_ids      = [each.value.sg]
  associate_public_ip_address = each.value.public_ip
  iam_instance_profile        = each.value.profile
  disable_api_termination     = var.protect_instances

  # IMDSv2 only; hop limit 2 so containers on the host can still reach it.
  # All five instances already have exactly these settings.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = each.value.volume_gb
    encrypted   = false
  }

  tags = {
    Name = each.value.name
  }

  lifecycle {
    # An AMI or user-data change, or a public-IP flag that differs after a
    # restart, must never replace a server that holds state (GitLab, Jenkins, Minikube).
    ignore_changes = [ami, user_data, associate_public_ip_address]
  }
}
