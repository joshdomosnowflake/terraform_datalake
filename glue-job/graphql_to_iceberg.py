import sys
import json
import requests
from datetime import datetime
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import SparkSession
from pyspark.sql.functions import current_timestamp, lit, col
from pyspark.sql.types import *

# Parse job arguments
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'GRAPHQL_ENDPOINT', 
    'GRAPHQL_QUERY_SHOWS',
    'GRAPHQL_QUERY_EPISODES',
    'S3_BUCKET',
    'DATABASE_NAME',
    'TABLE_NAME_SHOWS',
    'TABLE_NAME_EPISODES'
])

# Initialize Spark and Glue contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

def fetch_graphql_data(endpoint, query, query_name=""):
    """Fetch data from GraphQL endpoint"""
    try:
        print(f"Fetching {query_name} data from GraphQL API...")
        
        headers = {
            'Content-Type': 'application/json',
            # Add authentication headers if needed
            # 'Authorization': 'Bearer YOUR_TOKEN'
        }
        
        response = requests.post(
            endpoint,
            json={'query': query},
            headers=headers,
            timeout=30
        )
        
        response.raise_for_status()
        data = response.json()
        
        if 'errors' in data:
            raise Exception(f"GraphQL errors for {query_name}: {data['errors']}")
            
        return data.get('data', {})
        
    except Exception as e:
        print(f"Error fetching {query_name} GraphQL data: {str(e)}")
        raise

def infer_schema_from_data(sample_data):
    """Infer Spark schema from sample data"""
    if not sample_data:
        return None
        
    fields = []
    sample_record = sample_data[0] if isinstance(sample_data, list) else sample_data
    
    for key, value in sample_record.items():
        if isinstance(value, str):
            fields.append(StructField(key, StringType(), True))
        elif isinstance(value, int):
            fields.append(StructField(key, LongType(), True))
        elif isinstance(value, float):
            fields.append(StructField(key, DoubleType(), True))
        elif isinstance(value, bool):
            fields.append(StructField(key, BooleanType(), True))
        elif isinstance(value, dict):
            fields.append(StructField(key, StringType(), True))
        elif isinstance(value, list):
            fields.append(StructField(key, StringType(), True))
        else:
            fields.append(StructField(key, StringType(), True))
    
    return StructType(fields)

def clean_data_for_spark(data):
    """Clean and prepare data for Spark DataFrame creation"""
    if isinstance(data, list):
        cleaned_data = []
        for record in data:
            cleaned_record = {}
            for key, value in record.items():
                if isinstance(value, (dict, list)):
                    cleaned_record[key] = json.dumps(value)
                elif value is None:
                    cleaned_record[key] = None
                else:
                    cleaned_record[key] = value
            cleaned_data.append(cleaned_record)
        return cleaned_data
    return data

def extract_data_from_response(raw_data, data_type):
    """Extract data from GraphQL response based on expected structure"""
    if not raw_data:
        print(f"No {data_type} data returned from GraphQL API")
        return None
        
    possible_keys = list(raw_data.keys())
    
    if len(possible_keys) == 1:
        extracted_data = raw_data[possible_keys[0]]
    else:
        extracted_data = raw_data
    
    if not extracted_data:
        print(f"No {data_type} records found in GraphQL response")
        return None
        
    if not isinstance(extracted_data, list):
        extracted_data = [extracted_data]
        
    return extracted_data

def process_query_data(endpoint, query, query_name, table_name, database_name):
    """Process a single GraphQL query and write to Iceberg table"""
    try:
        raw_data = fetch_graphql_data(endpoint, query, query_name)
        extracted_data = extract_data_from_response(raw_data, query_name)
        
        if not extracted_data:
            print(f"Skipping {query_name} - no data to process")
            return False
            
        print(f"Found {len(extracted_data)} {query_name} records")
        
        cleaned_data = clean_data_for_spark(extracted_data)
        schema = infer_schema_from_data(cleaned_data)
        
        if not schema:
            print(f"Could not infer schema for {query_name} data")
            return False
            
        df = spark.createDataFrame(cleaned_data, schema)
        
        df_with_metadata = df.withColumn("ingestion_timestamp", current_timestamp()) \
                            .withColumn("source", lit("graphql_api")) \
                            .withColumn("data_type", lit(query_name)) \
                            .withColumn("job_run_id", lit(args.get('JOB_RUN_ID', 'manual')))
        
        df_final = df_with_metadata.withColumn("year", col("ingestion_timestamp").cast("date").cast("string").substr(1, 4)) \
                                  .withColumn("month", col("ingestion_timestamp").cast("date").cast("string").substr(6, 2)) \
                                  .withColumn("day", col("ingestion_timestamp").cast("date").cast("string").substr(9, 2))
        
        # Clean database and table names for Spark SQL compatibility
        clean_database_name = database_name.replace("-", "_")
        clean_table_name = table_name.replace("-", "_")
        full_table_name = f"glue_catalog.{clean_database_name}.{clean_table_name}"
        
        print(f"Writing {df_final.count()} {query_name} records to Iceberg table: {full_table_name}")
        
        # Write to Iceberg table using Glue Catalog
        df_final.writeTo(full_table_name) \
                .using("iceberg") \
                .option("write.format.default", "parquet") \
                .option("write.parquet.compression-codec", "snappy") \
                .partitionedBy("year", "month", "day") \
                .createOrReplace()
        
        print(f"Successfully wrote {query_name} data to Iceberg table")
        print(f"Sample {query_name} data written:")
        spark.sql(f"SELECT * FROM {full_table_name} LIMIT 3").show(truncate=False)
        
        return True
        
    except Exception as e:
        print(f"Error processing {query_name} data: {str(e)}")
        raise

def main():
    print(f"Starting GraphQL to Iceberg job: {args['JOB_NAME']}")
    print(f"GraphQL endpoint: {args['GRAPHQL_ENDPOINT']}")
    print(f"Target database: {args['DATABASE_NAME']}")
    print(f"Target tables: {args['TABLE_NAME_SHOWS']}, {args['TABLE_NAME_EPISODES']}")
    
    success_count = 0
    total_queries = 2
    
    try:
        print("\n" + "="*50)
        print("PROCESSING SHOWS DATA")
        print("="*50)
        
        if process_query_data(
            args['GRAPHQL_ENDPOINT'],
            args['GRAPHQL_QUERY_SHOWS'],
            "shows",
            args['TABLE_NAME_SHOWS'],
            args['DATABASE_NAME']
        ):
            success_count += 1
        
        print("\n" + "="*50)
        print("PROCESSING EPISODES DATA")
        print("="*50)
        
        if process_query_data(
            args['GRAPHQL_ENDPOINT'],
            args['GRAPHQL_QUERY_EPISODES'],
            "episodes",
            args['TABLE_NAME_EPISODES'],
            args['DATABASE_NAME']
        ):
            success_count += 1
        
        print("\n" + "="*50)
        print("JOB SUMMARY")
        print("="*50)
        print(f"Successfully processed {success_count}/{total_queries} queries")
        
        if success_count == 0:
            raise Exception("No queries were processed successfully")
        elif success_count < total_queries:
            print(f"Warning: Only {success_count}/{total_queries} queries processed successfully")
        else:
            print("All queries processed successfully!")
        
    except Exception as e:
        print(f"Job failed with error: {str(e)}")
        raise
    
    finally:
        job.commit()

if __name__ == "__main__":
    main()