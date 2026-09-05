terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure if you want remote state (recommended once this
  # is more than a demo lab):
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "devops-lab-infra/terraform.tfstate"
  #   region = "ap-south-1"
  # }
}

provider "aws" {
  region = var.aws_region
}
