provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Course      = "ACS730"
      Assignment  = "assign1"
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}
