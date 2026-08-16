output "dev_s3_bucket_name" {
  description = "Name of the development S3 bucket"
  value       = module.secure_storage.bucket_id
}

output "dev_security_group_id" {
  description = "ID of the development security group"
  value       = module.secure_networking.security_group_id
}
