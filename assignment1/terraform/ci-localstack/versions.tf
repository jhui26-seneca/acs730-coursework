terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend on purpose: LocalStack state is throwaway and must never touch
  # the real S3 state bucket (or any real environment's key).
}
