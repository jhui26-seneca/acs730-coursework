# Final project, staging: the VM half of the application (Apache, configured by the Assignment 2
# role). This is the environment the deploy pipeline applies on every merge to main, through the
# GitHub Environment "final". It reuses the Assignment 1 module unchanged: same code as
# assign1's dev, staging and prod, different values.
module "web_env" {
  source = "../../../assignment1/terraform/modules/web-env"

  environment                = "staging"
  vpc_cidr                   = "10.40.0.0/16"
  instance_type              = "t3.micro"
  detailed_monitoring        = true
  cpu_alarm_threshold        = 70
  db_password_parameter_name = "/acs730/assign1/final-staging/db_password"
}
