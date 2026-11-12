terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # The term-long state bucket from Lab 3, with the final project's own key per environment.
  backend "s3" {
    bucket       = "acs730-tfstate-572751986246"
    key          = "final-project/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
