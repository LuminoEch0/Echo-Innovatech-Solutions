terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  backend "s3" {
    bucket       = "fontys-cs-tfstate-innovatech"   
    key          = "cs2/terraform.tfstate"
    region       = "eu-central-1"               
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}