terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Same bucket as Labs 3 and 6, but this environment's OWN key.
  backend "s3" {
    bucket       = "acs730-tfstate-572751986246"
    key          = "assign1/dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
