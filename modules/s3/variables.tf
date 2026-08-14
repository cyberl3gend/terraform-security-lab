variable "bucket_name" {
  type = string
  description = "The unique name of the s3 bucket to create"
}

variable "environment" {
  type = string
  description = "The target deployment environment"
  default = "dev"
}
