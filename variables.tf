variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "graphql-iceberg"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
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

variable "graphql_query_shows" {
  description = "GraphQL query for shows data" 
  type        = string
}

variable "graphql_query_episodes" {
  description = "GraphQL query for episodes data"
  type        = string
}

variable "snowflake_account_locator" {
  description = "Snowflake account locator (e.g., ABC12345.us-east-1)"
  type        = string
  default     = ""
}

variable "snowflake_aws_external_id" {
  description = "External ID from Snowflake storage integration"
  type        = string
  default     = ""
}

variable "snowflake_aws_iam_user_arn" {
  description = "AWS IAM User ARN from Snowflake storage integration"
  type        = string
  default     = ""
}

variable "enable_snowflake_integration" {
  description = "Enable Snowflake S3 integration"
  type        = bool
  default     = false
}