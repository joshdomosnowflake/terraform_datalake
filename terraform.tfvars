project_name = "graphql-iceberg"
aws_region   = "us-west-2"

graphql_endpoint = "https://graphql.anilist.co"

graphql_query_shows = <<-EOT
query {
  Page {
    pageInfo {
      hasNextPage
    }
    media (isAdult: false) {
      id    
      title {
        english
      }
      meanScore
      description
      duration
      genres
      episodes
      format
      countryOfOrigin
      startDate {
        day
        month
        year
      }
  }
}
}
EOT

graphql_query_episodes = <<-EOT
query {
  Page {
    pageInfo {
      hasNextPage
    }
    media (isAdult: false) {
      id
      streamingEpisodes {
        site
        title
        url
      }
  }
}
}
EOT
