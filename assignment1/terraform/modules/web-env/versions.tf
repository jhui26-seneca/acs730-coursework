terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # A module never configures its own provider or backend: each caller
  # (dev, staging, prod, ci-localstack) does that, with its own state key.
}
