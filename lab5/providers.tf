# One provider, two targets: real AWS (default) or LocalStack (use_localstack = true).
provider "aws" {
  region = var.aws_region

  # LocalStack accepts any non-empty keys. null = normal AWS credential chain.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  s3_use_path_style           = var.use_localstack # without this, only the bucket fails

  dynamic "endpoints" {
    for_each = var.use_localstack ? [var.localstack_endpoint] : []
    content {
      ec2 = endpoints.value
      s3  = endpoints.value
      sts = endpoints.value
    }
  }

  default_tags {
    tags = local.common_tags
  }
}
