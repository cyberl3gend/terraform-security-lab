output "prod_s3_bucket_name" {
  description = "Name of the production S3 bucket"
  value       = module.prod_storage.bucket_id
}

output "prod_security_group_id" {
  description = "ID of the production security group"
  value       = module.prod_networking.security_group_id
}
