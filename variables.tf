variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
  default     = "simple-nfw-lab"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR"
  default     = "10.50.0.0/16"
}

variable "workload_subnet_cidr" {
  type        = string
  description = "Subnet for the test EC2 instance"
  default     = "10.50.1.0/24"
}

variable "firewall_subnet_1_cidr" {
  type        = string
  description = "Firewall subnet in AZ1"
  default     = "10.50.100.0/24"
}

variable "firewall_subnet_2_cidr" {
  type        = string
  description = "Firewall subnet in AZ2"
  default     = "10.50.101.0/24"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "Optional SSH source CIDR. SSM is preferred."
  default     = "0.0.0.0/32"
}
