output "bucket_arn" {
  description = "The Amazon Resource Name (ARN) of the created bucket"
  value       = aws_s3_bucket.this.arn

}

output "bucket_id" {
  description = "The ID/Name of the created S3 bucket"
  value       = aws_s3_bucket.this.id
}
