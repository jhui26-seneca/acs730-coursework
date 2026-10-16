output "environment" {
  description = "Environment this module call built."
  value       = var.environment
}

output "vpc_id" {
  description = "ID of the environment's VPC."
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Public subnet IDs, keyed a and b."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "security_group_id" {
  description = "ID of the web security group (HTTP only)."
  value       = aws_security_group.web.id
}

output "instance_id" {
  description = "ID of the web server instance."
  value       = aws_instance.web.id
}

output "web_public_ip" {
  description = "Public IP of the web server."
  value       = aws_instance.web.public_ip
}

output "web_url" {
  description = "URL of the web page."
  value       = "http://${aws_instance.web.public_ip}"
}

output "cpu_alarm_name" {
  description = "Name of the CloudWatch CPU alarm."
  value       = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}

output "db_password_parameter_name" {
  description = "SSM parameter the data source read."
  value       = data.aws_ssm_parameter.db_password.name
}

output "db_password_parameter_version" {
  description = "Version of the SSM parameter the data source read."
  value       = data.aws_ssm_parameter.db_password.version
}

output "db_password" {
  description = "The value the data source read - sensitive, shown only with terraform output -raw."
  value       = data.aws_ssm_parameter.db_password.value
  sensitive   = true
}
