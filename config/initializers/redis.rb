# frozen_string_literal: true

# Redis connection for slot locks and other ephemeral data
# Uses ElastiCache Serverless (Valkey) in production, local Redis in development

REDIS = if ENV["REDIS_URL"].present?
  redis_url = ENV["REDIS_URL"]

  # Add scheme if missing (ElastiCache URLs sometimes don't include it)
  unless redis_url.start_with?("redis://", "rediss://")
    # Use TLS for AWS ElastiCache
    scheme = redis_url.include?("amazonaws.com") ? "rediss://" : "redis://"
    redis_url = "#{scheme}#{redis_url}"
  end

  # Use SSL for AWS ElastiCache connections
  use_ssl = redis_url.include?("amazonaws.com") || redis_url.start_with?("rediss://")

  Redis.new(url: redis_url, ssl: use_ssl)
else
  # Development/test: connect to local Redis if available, otherwise use a null object
  begin
    redis = Redis.new(url: "redis://localhost:6379/0")
    redis.ping # Test connection
    redis
  rescue Redis::CannotConnectError
    # No local Redis running - return nil (slot locks will be disabled)
    Rails.logger.warn "Redis not available - slot locks will be disabled"
    nil
  end
end
