data "aws_vpc" "default" {
  default = true
}

module "secure_storage" {
  source = "./modules/s3"

  bucket_name = "security-lab-bucket-jon-2026"
  environment = "dev"
}

module "secure_networking" {
  source = "./modules/networking"

  vpc_id      = data.aws_vpc.default.id
  environment = "dev"
}
