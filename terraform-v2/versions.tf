terraform {
  required_version = ">= 1.7.0" # import blocks with for_each need 1.7+, plain import blocks 1.5+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}
