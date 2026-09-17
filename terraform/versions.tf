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

  # Partial backend configuration. Bucket and region are supplied at init time so
  # the same code works across accounts:
  #
  #   terraform init -backend-config=backend.hcl        (local, see backend.hcl.example)
  #   terraform init -backend-config="bucket=..." ...   (CI, see the terraform-plan job)
  #
  # Remote state is mandatory once CI applies this. With local state, every
  # pipeline run starts from an empty state file and tries to build a second copy
  # of the whole stack.
  #
  # use_lockfile enables S3-native state locking, so no DynamoDB table is needed.
  # Create the bucket first with scripts/bootstrap-state.sh.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}
