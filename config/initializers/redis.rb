# frozen_string_literal: true

# Redis connection for slot locks and other ephemeral data
# Uses ElastiCache Serverless (Valkey) in production, local Redis in development

REDIS = if ENV["REDIS_URL"].present?
  Redis.new(url: ENV["REDIS_URL"], ssl: ENV["REDIS_URL"].include?("amazonaws.com"))
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
