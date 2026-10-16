# This caller only ever targets LocalStack, in the pull-request check.
locals {
  localstack_endpoint = "http://localhost:4566"
}

provider "aws" {
  region = "us-east-1"

  # LocalStack accepts any non-empty keys; no real credential is ever used here.
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  endpoints {
    cloudwatch = local.localstack_endpoint
    ec2        = local.localstack_endpoint
    iam        = local.localstack_endpoint
    ssm        = local.localstack_endpoint
    sts        = local.localstack_endpoint
  }

  default_tags {
    tags = {
      Course      = "ACS730"
      Assignment  = "assign1"
      Environment = "ci"
      ManagedBy   = "terraform"
    }
  }
}
