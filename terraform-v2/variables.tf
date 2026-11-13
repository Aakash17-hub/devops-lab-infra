variable "region" {
  description = "AWS region of the lab."
  type        = string
  default     = "ap-southeast-1"
}

variable "az" {
  description = "Availability zone of both subnets."
  type        = string
  default     = "ap-southeast-1a"
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
  description = "Ubuntu 24.04 AMI used by all instances. Set in terraform.tfvars (not committed)."
  type        = string
}

variable "key_name" {
  description = "Name of an existing EC2 key pair. Set in terraform.tfvars (not committed)."
  type        = string
}

variable "admin_cidr" {
  description = "Your public IP as a /32. Only this address can reach the bastion on SSH. Set in terraform.tfvars (not committed)."
  type        = string
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
