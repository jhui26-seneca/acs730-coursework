# Final project, prod: written and validated to keep the multi-environment pattern, never applied.
# The deploy pipeline applies only staging; this caller is checked by final-ci (terraform validate)
# and by the required tfsec check. It reuses the Assignment 1 module in place, with prod's values.
module "web_env" {
  source = "../../../assignment1/terraform/modules/web-env"

  environment                = "prod"
  vpc_cidr                   = "10.50.0.0/16"
  instance_type              = "t3.micro"
  detailed_monitoring        = true
  cpu_alarm_threshold        = 60
  db_password_parameter_name = "/acs730/assign1/final-prod/db_password"
}
