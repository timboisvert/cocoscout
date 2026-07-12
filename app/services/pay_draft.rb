# frozen_string_literal: true

# Server-side draft for the staff Pay People form. Stores an opaque JSON blob
# (managed by the client) in the cache, keyed per user + org, so an in-progress
# pay run survives navigation and reloads and is cleared once the run is paid.
module PayDraft
  TTL = 24.hours

  module_function

  def cache_key(user, organization)
    "staff_pay_draft:#{user.id}:#{organization.id}"
  end

  def read(user, organization)
    Rails.cache.read(cache_key(user, organization))
  end

  def write(user, organization, blob)
    Rails.cache.write(cache_key(user, organization), blob.to_s, expires_in: TTL)
  end

  def clear(user, organization)
    Rails.cache.delete(cache_key(user, organization))
  end
end
