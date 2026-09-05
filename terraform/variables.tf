variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix applied to all resources"
  type        = string
  default     = "devops-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public (DMZ-equivalent) subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private (LAN-equivalent) subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair to use for SSH access"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your IP address in CIDR form, allowed to reach the bastion on port 22 (e.g. 203.0.113.5/32)"
  type        = string
}

variable "instance_type" {
  description = "Instance type for lab EC2 instances"
  type        = string
  default     = "t3.micro"
}
