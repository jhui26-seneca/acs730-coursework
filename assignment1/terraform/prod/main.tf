# prod: deployed by the pipeline only after a required reviewer approves
# (GitHub Environment "prod", main branch only). Same module as dev and staging.
module "web_env" {
  source = "../modules/web-env"

  environment                = "prod"
  vpc_cidr                   = "10.30.0.0/16"
  instance_type              = "t3.micro"
  detailed_monitoring        = true
  cpu_alarm_threshold        = 60
  db_password_parameter_name = "/acs730/assign1/prod/db_password"
}
