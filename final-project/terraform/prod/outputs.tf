output "environment" {
  value = module.web_env.environment
}

output "instance_id" {
  value = module.web_env.instance_id
}

# The Kubernetes side reads this: the Flask app calls the VM at this address.
output "web_url" {
  value = module.web_env.web_url
}

output "cpu_alarm_name" {
  value = module.web_env.cpu_alarm_name
}

output "status_alarm_name" {
  value = module.web_env.status_alarm_name
}

output "db_password_parameter_version" {
  value = module.web_env.db_password_parameter_version
}
