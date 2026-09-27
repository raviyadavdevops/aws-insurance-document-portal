variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources."
  type        = string
  default     = "insurance-doc-portal"
}

variable "availability_zones" {
  description = "Exactly two Availability Zones to deploy across."
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two Availability Zones are required for this MVP."
  }
}

variable "db_username" {
  description = "RDS PostgreSQL master username. No default — must be supplied via terraform.tfvars (never hard-coded)."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS PostgreSQL master password. No default — must be supplied via terraform.tfvars (never hard-coded)."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Name of the PostgreSQL database."
  type        = string
  default     = "insurance_documents"
}

variable "instance_type" {
  description = "EC2 instance type for the Flask application."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}
