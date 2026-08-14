variable "vpc_id" {
  type        = string
  description = "The ID of the VPC where the security group will be created"
}

variable "environment" {
  type        = string
  description = "The target environment"
  default     = "dev"
}

variable "allowed_ingress_ports" {
  type        = list(number)
  description = "List of allowed inbound ports"
  default     = [443]
}
