output "vpc_id" {
  description = "ID of the lab5 VPC."
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Public subnet IDs, keyed a and b."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "web_public_ip" {
  description = "Public IP of the web server."
  value       = aws_instance.web.public_ip
}

output "web_url" {
  description = "URL of the web page (only answers on real AWS; LocalStack never boots user_data)."
  value       = "http://${aws_instance.web.public_ip}"
}

output "provider_target" {
  description = "Where this run sent its API calls - read this before trusting any plan."
  value       = var.use_localstack ? "localstack (${var.localstack_endpoint})" : "aws (REAL account)"
}

output "bucket_name" {
  description = "Artifacts bucket name, or null when create_bucket is false."
  value       = one(aws_s3_bucket.artifacts[*].bucket)
}
