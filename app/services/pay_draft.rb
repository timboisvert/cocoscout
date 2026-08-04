# frozen_string_literal: true

# Server-side draft for the staff Pay People form. Stores an opaque JSON blob
# (managed by the client) in the cache, keyed per ORGANIZATION — the in-progress
# pay run belongs to the org, not to whoever happens to be typing, so co-owners
# and managers all see and continue the same draft. Survives navigation and
# reloads; cleared once the run is submitted. Last write wins if two managers
# edit at once (autosave is debounced per keystroke, so this converges fast).
module PayDraft
  TTL = 24.hours

  module_function

  def cache_key(organization)
    "staff_pay_draft:org:#{organization.id}"
  end

  def read(organization)
    Rails.cache.read(cache_key(organization))
  end

  def write(organization, blob)
    Rails.cache.write(cache_key(organization), blob.to_s, expires_in: TTL)
  end

  def clear(organization)
    Rails.cache.delete(cache_key(organization))
  end
end
