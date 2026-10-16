output "environment" {
  value = module.web_env.environment
}

output "instance_id" {
  value = module.web_env.instance_id
}

output "web_url" {
  value = module.web_env.web_url
}

output "cpu_alarm_name" {
  value = module.web_env.cpu_alarm_name
}

output "db_password_parameter_name" {
  value = module.web_env.db_password_parameter_name
}

output "db_password_parameter_version" {
  value = module.web_env.db_password_parameter_version
}

output "db_password" {
  value     = module.web_env.db_password
  sensitive = true
}
