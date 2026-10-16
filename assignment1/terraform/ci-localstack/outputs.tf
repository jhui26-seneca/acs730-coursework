output "account_id" {
  description = "000000000000 on LocalStack - the CI guard refuses anything else."
  value       = data.aws_caller_identity.current.account_id
}

output "cpu_alarm_name" {
  value = module.web_env.cpu_alarm_name
}

output "db_password_parameter_version" {
  value = module.web_env.db_password_parameter_version
}
