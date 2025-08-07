terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-datalake-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name = "${var.project_name}-datalake"
  }
}

resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${var.project_name}-scripts-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name = "${var.project_name}-scripts"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_glue_catalog_database" "data_lake_db" {
  name        = replace("${var.project_name}_db", "-", "_")  # Replace hyphens with underscores
  description = "Database for ${var.project_name}"
  catalog_id  = data.aws_caller_identity.current.account_id
}

resource "aws_iam_role" "glue_job_role" {
  name = "${var.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_policy" {
  name = "${var.project_name}-s3-policy"
  role = aws_iam_role.glue_job_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*",
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_glue_job" "graphql_job" {
  name         = "${var.project_name}-processor"
  role_arn     = aws_iam_role.glue_job_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-glue-datacatalog"          = "true"
    
    # Add ALL required Iceberg JARs with dependencies
    "--extra-jars" = join(",", [
      "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.3_2.12/1.3.1/iceberg-spark-runtime-3.3_2.12-1.3.1.jar",
      "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws/1.3.1/iceberg-aws-1.3.1.jar",
      "https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.20.18/bundle-2.20.18.jar",
      "https://repo1.maven.org/maven2/software/amazon/awssdk/url-connection-client/2.20.18/url-connection-client-2.20.18.jar"
    ])
    
    # Iceberg + Glue Catalog configuration
    "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.warehouse=s3://${aws_s3_bucket.data_lake.bucket}/warehouse/ --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO"
    
    # Your application arguments
    "--GRAPHQL_ENDPOINT"                = var.graphql_endpoint
    "--GRAPHQL_QUERY_SHOWS"             = var.graphql_query_shows
    "--GRAPHQL_QUERY_EPISODES"          = var.graphql_query_episodes
    "--S3_BUCKET"                       = aws_s3_bucket.data_lake.bucket
    "--DATABASE_NAME"                   = aws_glue_catalog_database.data_lake_db.name
    "--TABLE_NAME_SHOWS"                = "shows"
    "--TABLE_NAME_EPISODES"             = "episodes"
    "--additional-python-modules"       = "requests==2.28.2,gql[all]==3.4.1"
  }

  max_capacity = 2
  timeout      = 45

  tags = {
    Name        = "${var.project_name}-processor"
    Environment = "dev"
  }
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/graphql_to_iceberg.py"
  source = "glue-job/graphql_to_iceberg.py"
  etag   = filemd5("glue-job/graphql_to_iceberg.py")
  
  tags = {
    Name = "GraphQL to Iceberg Script"
  }
}

resource "aws_iam_role" "snowflake_s3_role" {
  count = var.enable_snowflake_integration ? 1 : 0
  
  name = "${var.project_name}-snowflake-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.snowflake_aws_iam_user_arn
        }
        Action = "sts:AssumeRole"
        Condition = var.snowflake_aws_external_id != "" ? {
          StringEquals = {
            "sts:ExternalId" = var.snowflake_aws_external_id
          }
        } : {}
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-snowflake-role"
    Environment = var.environment
    Purpose     = "Snowflake S3 Integration"
  }
}

resource "aws_iam_role_policy" "snowflake_s3_policy" {
  count = var.enable_snowflake_integration ? 1 : 0
  
  name = "${var.project_name}-snowflake-s3-policy"
  role = aws_iam_role.snowflake_s3_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetDatabase",
          "glue:GetPartitions",
          "glue:GetTables",
          "glue:GetDatabases"
        ]
        Resource = "*"
      }
    ]
  })
}

# Outputs for Snowflake configuration
output "snowflake_role_arn" {
  description = "IAM Role ARN for Snowflake integration"
  value       = var.enable_snowflake_integration ? aws_iam_role.snowflake_s3_role[0].arn : "Not enabled"
}

output "data_lake_warehouse_path" {
  description = "S3 warehouse path for Snowflake external volume"
  value       = "s3://${aws_s3_bucket.data_lake.bucket}/warehouse/"
}

output "snowflake_setup_commands" {
  description = "Snowflake SQL commands to run (after getting external ID)"
  value = var.enable_snowflake_integration ? templatefile("${path.module}/snowflake_commands.tftpl", {
    project_name   = var.project_name
    role_arn       = aws_iam_role.snowflake_s3_role[0].arn
    bucket_name    = aws_s3_bucket.data_lake.bucket
    database_name  = aws_glue_catalog_database.data_lake_db.name
  }) : "Snowflake integration not enabled"
}
