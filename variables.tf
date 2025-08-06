variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "graphql-to-iceberg"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "graphql_endpoint" {
  description = "GraphQL API endpoint"
  type        = string
}

variable "graphql_query" {
  description = "GraphQL query to execute"
  type        = string
}

variable "schedule_expression" {
  description = "CloudWatch Events schedule expression"
  type        = string
  default     = "rate(1 hour)"
}

variable "glue_job_timeout" {
  description = "Glue job timeout in minutes"
  type        = number
  default     = 60
}

variable "glue_job_max_capacity" {
  description = "Glue job max capacity (DPU)"
  type        = number
  default     = 2
}

variable "enable_schedule" {
  description = "Enable scheduled execution"
  type        = bool
  default     = true
}