# frozen_string_literal: true

# Rate limiting. Added after a Tor-exit crawler saturated a web host's Puma
# workers (slow image-variant requests + /signup POSTs) and wedged it into 30s
# proxy 504s for real users — with CPU flat, so no alarm fired. These throttles
# cap what any single IP can consume; legit users never come near them.
class Rack::Attack
  # Counters live in Redis (shared across Puma workers and both web hosts);
  # fall back to an in-process store when Redis isn't around (dev without redis).
  if defined?(REDIS) && REDIS
    Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(redis: REDIS)
  else
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

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
