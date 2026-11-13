# Lookups that make the lab portable to any account and region.

data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Canonical Ubuntu 24.04 LTS (amd64, gp3). Instances ignore later AMI changes.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Public IP of the machine running Terraform, for the bastion SSH rule.
# A dynamic IP is picked up again on every plan.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  az         = coalesce(var.az, data.aws_availability_zones.available.names[0])
  ami_id     = coalesce(var.ami_id, data.aws_ami.ubuntu.id)
  admin_cidr = coalesce(var.admin_cidr, "${chomp(data.http.my_ip.response_body)}/32")
}