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