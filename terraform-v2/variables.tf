variable "region" {
  description = "AWS region of the lab."
  type        = string
  default     = "ap-southeast-1"
}

variable "az" {
  description = "Availability zone of both subnets. Empty = the region's first AZ."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "ami_id" {
  description = "AMI for all instances. Empty = latest Canonical Ubuntu 24.04."
  type        = string
  default     = null
}

variable "key_name" {
  description = "Name of the key pair Terraform creates."
  type        = string
  default     = "devops-lab-key"
}

variable "public_key_path" {
  description = "Public half of your SSH key (ssh-keygen -y -f key.pem). Set in terraform.tfvars."
  type        = string
}

variable "admin_cidr" {
  description = "IP allowed to SSH to the bastion, as a /32. Empty = your current public IP, detected on every plan."
  type        = string
  default     = null
}

variable "protect_instances" {
  description = "Turn on EC2 termination protection. Set to false and apply before destroying."
  type        = bool
  default     = true
}

variable "enable_nat" {
  description = "Create a NAT gateway and route the private subnet through it. Costs money per hour; off by default."
  type        = bool
  default     = false
}