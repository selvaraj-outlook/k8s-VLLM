terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state is strongly recommended for shared infrastructure.
  # Create the bucket and lock table first, then uncomment and run `terraform init -migrate-state`.
  #
  # backend "s3" {
  #   bucket       = "my-tf-state-bucket"
  #   key          = "k8s-vllm/infra.tfstate"
  #   region       = "us-east-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
