terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block on purpose: LocalStack state is throwaway, so it stays in a
  # local (gitignored) terraform.tfstate and never touches the real S3 state bucket.
}
