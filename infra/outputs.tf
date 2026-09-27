output "alb_dns_name" {
  description = "Public DNS name of the ALB — open this in a browser to use the portal."
  value       = aws_lb.main.dns_name
}

output "s3_bucket_name" {
  description = "Name of the private document bucket."
  value       = aws_s3_bucket.documents.bucket
}

output "rds_endpoint" {
  description = "RDS PostgreSQL connection endpoint (host:port)."
  value       = aws_db_instance.postgres.endpoint
}

output "db_instance_id" {
  description = "RDS instance identifier, for teardown verification."
  value       = aws_db_instance.postgres.identifier
}

output "lambda_function_name" {
  description = "Name of the metadata-processing Lambda function."
  value       = aws_lambda_function.metadata_processor.function_name
}
