# The pull-request check: the SAME module, applied and destroyed against LocalStack.
module "web_env" {
  source = "../modules/web-env"

  environment                = "ci"
  vpc_cidr                   = "10.99.0.0/16"
  instance_type              = "t3.micro"
  ami_name_filter            = "amzn2-ami-hvm-*-x86_64-gp2" # the image LocalStack ships
  detailed_monitoring        = false                        # LocalStack does not implement MonitorInstances (HTTP 501)
  cpu_alarm_threshold        = 80
  db_password_parameter_name = "/acs730/assign1/ci/db_password"
}

data "aws_caller_identity" "current" {}
