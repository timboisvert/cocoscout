# frozen_string_literal: true

# Rate limiting. Added after a Tor-exit crawler saturated a web host's Puma
# workers (slow image-variant requests + /signup POSTs) and wedged it into 30s
# proxy 504s for real users — with CPU flat, so no alarm fired. These throttles
# cap what any single IP can consume; legit users never come near them.
class Rack::Attack
  # Never throttle the load balancer's health checks or in-VPC traffic.
  safelist("health-checks-and-vpc") do |req|
    req.path == "/up" || req.ip.to_s.start_with?("10.")
  end

  # General per-IP ceiling on dynamic requests. Assets are cheap and cached —
  # leave them out so a busy page load doesn't eat the budget.
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/assets")
  end

  # Auth endpoints: brute-force and bot-signup protection.
  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.post? && [ "/signin", "/signup" ].include?(req.path)
  end

  # Active Storage variants are expensive (image processing / S3 fetch) — the
  # exact resource the crawler used to tie up every worker thread.
  throttle("blobs/ip", limit: 120, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/rails/active_storage")
  end

  self.throttled_responder = lambda do |_request|
    [ 429, { "Content-Type" => "text/plain" }, [ "Too many requests. Slow down and try again shortly.\n" ] ]
  end
end

# Don't interfere with the test suite's rapid-fire requests.
Rack::Attack.enabled = !Rails.env.test?

# Counter store: Redis, shared across Puma workers and both web hosts, so the
# limits mean what they say. Set after boot because initializers load
# alphabetically and the REDIS constant is defined in redis.rb, which loads
# AFTER this file ("rack_attack" < "redis"). Falls back to an in-process store
# (per-worker counters — looser, but still protective) when Redis isn't around.
Rails.application.config.after_initialize do
  Rack::Attack.cache.store =
    if defined?(REDIS) && REDIS
      ActiveSupport::Cache::RedisCacheStore.new(redis: REDIS)
    else
      ActiveSupport::Cache::MemoryStore.new
    end
end
