terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

module "prod_networking" {
  source = "../../modules/networking"

  environment = "prod"
  vpc_cidr    = "10.1.0.0/16"
}

module "prod_storage" {
  source = "../../modules/s3"

  environment = "prod"
  bucket_name = "prod-app-storage-lab-2026"
}
