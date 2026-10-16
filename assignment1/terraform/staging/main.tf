# staging: deployed by the pipeline on every merge to main (GitHub Environment
# "staging", no reviewer). Same module as dev and prod; only the values differ.
module "web_env" {
  source = "../modules/web-env"

  environment                = "staging"
  vpc_cidr                   = "10.20.0.0/16"
  instance_type              = "t3.micro"
  detailed_monitoring        = true
  cpu_alarm_threshold        = 70
  db_password_parameter_name = "/acs730/assign1/staging/db_password"
}
