# dev: created and destroyed from the workstation by scripts/create-dev.sh and
# scripts/destroy-env.sh. The pipeline never deploys dev.
module "web_env" {
  source = "../modules/web-env"

  environment                = "dev"
  vpc_cidr                   = "10.10.0.0/16"
  instance_type              = "t3.micro"
  detailed_monitoring        = false
  cpu_alarm_threshold        = 80
  db_password_parameter_name = "/acs730/assign1/dev/db_password"
}
