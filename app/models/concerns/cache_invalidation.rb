# frozen_string_literal: true

# Provides cache invalidation helpers for models.
# Include this concern and call `invalidates_cache` to set up automatic cache invalidation.
#
# Usage:
#   class Person < ApplicationRecord
#     include CacheInvalidation
#     invalidates_cache :person_card, :person_profile
#   end
#
# This will call `invalidate_person_card_cache` and `invalidate_person_profile_cache`
# after save and after destroy.
#
# You can also manually invalidate caches:
#   person.invalidate_cache(:person_card)
#   Person.invalidate_all_caches(:person_card)
#
module CacheInvalidation
  extend ActiveSupport::Concern

  included do
    class_attribute :cache_keys_to_invalidate, default: []
  end

  class_methods do
    # Declare which cache keys this model invalidates
    def invalidates_cache(*cache_names)
      self.cache_keys_to_invalidate = cache_names

      after_commit :invalidate_all_declared_caches, on: [:create, :update, :destroy]
    end

    # Invalidate all caches for all records of this model
    # NOTE: Solid Cache doesn't support delete_matched, so this is a no-op.
    # Use cache key versioning (include updated_at in keys) for automatic invalidation.
    def invalidate_all_caches(cache_name)
      Rails.logger.warn("invalidate_all_caches called for #{cache_name} but Solid Cache doesn't support delete_matched. Use cache key versioning instead.")
    end
  end

  # Invalidate a specific cache for this record
  def invalidate_cache(cache_name)
    cache_key = "#{cache_name}_#{self.class.name}_#{id}"
    Rails.cache.delete(cache_key)
    Rails.logger.debug { "Cache invalidated: #{cache_key}" }
  end

  # Get a cache key for this record
  def cache_key_for(cache_name)
    "#{cache_name}_#{self.class.name}_#{id}"
  end

  private

  def invalidate_all_declared_caches
    cache_keys_to_invalidate.each do |cache_name|
      invalidate_cache(cache_name)
    end
  end
end
