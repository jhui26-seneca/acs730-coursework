# Every resource the module creates gets these tags. Project = final tells these apart from
# Assignment 1's (the module's own name prefix is fixed at acs730-assign1-<environment>), and
# Role = web is the tag the final project's Ansible inventory selects the VM by.
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Course      = "ACS730"
      Project     = "final"
      Environment = "prod"
      Role        = "web"
      ManagedBy   = "terraform"
    }
  }
}
