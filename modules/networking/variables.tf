variable "environment" {
  type        = string
  description = "The target environment"
}

variable "allowed_ingress_ports" {
  type        = list(number)
  description = "List of allowed inbound ports"
  default     = [443]
}

variable "vpc_cidr" {
  type = string
  description = "CIDR block for the VPC"
  default = "10.0.0.0/16"
}
