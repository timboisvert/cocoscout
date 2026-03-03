# frozen_string_literal: true

# Manages temporary spot holds for course offerings using Redis.
# When a user clicks "Pay & Register", a 5-minute hold is acquired on one spot.
# This prevents overselling while the user completes payment on Stripe.
# The CourseRegistration is only created AFTER successful payment (via webhook).
#
# Usage:
#   CourseSpotHoldService.acquire(offering_id, person_id)  # => { success: true, expires_in: 300 }
#   CourseSpotHoldService.release(offering_id, person_id)  # => true
#   CourseSpotHoldService.held?(offering_id, person_id)    # => true/false
#   CourseSpotHoldService.active_holds_count(offering_id)  # => 2
#
class CourseSpotHoldService
  HOLD_DURATION = 5.minutes.to_i  # 300 seconds
  KEY_PREFIX = "course_hold"
  SET_PREFIX = "course_holds_set"

  class << self
    # Acquire a spot hold for a person on a course offering.
    # Returns hash with :success, :expires_in, :error
    def acquire(offering_id, person_id)
      return { success: false, error: "Redis not available" } unless redis_available?

      key = hold_key(offering_id, person_id)

      # Use SET with NX (only if not exists) and EX (expiry) — atomic and race-safe
      result = redis.set(key, person_id.to_s, nx: true, ex: HOLD_DURATION)

      if result
        # Track this person in a set for efficient counting
        redis.sadd(set_key(offering_id), person_id.to_s)
        { success: true, expires_in: HOLD_DURATION }
      else
        # Already holding — extend the hold (same person clicking again)
        redis.expire(key, HOLD_DURATION)
        { success: true, expires_in: HOLD_DURATION, extended: true }
      end
    end

    # Release a spot hold (called after successful payment or cancellation)
    def release(offering_id, person_id)
      return false unless redis_available?

      key = hold_key(offering_id, person_id)
      redis.del(key)
      redis.srem(set_key(offering_id), person_id.to_s)
      true
    end

    # Check if a specific person has an active hold
    def held?(offering_id, person_id)
      return false unless redis_available?
      redis.exists?(hold_key(offering_id, person_id))
    end

    # Count active holds for a course offering.
    # Cleans up expired entries from the tracking set lazily.
    def active_holds_count(offering_id)
      return 0 unless redis_available?

      skey = set_key(offering_id)
      members = redis.smembers(skey)
      return 0 if members.empty?

      # Pipeline-check which hold keys still exist (not expired)
      results = {}
      redis.pipelined do |pipeline|
        members.each do |person_id|
          results[person_id] = pipeline.exists?(hold_key(offering_id, person_id))
        end
      end

      active_count = 0
      expired = []

      results.each do |person_id, future|
        # exists? returns integer in pipeline (1 = exists, 0 = not)
        exists = begin
          val = future.value
          val == true || val == 1
        rescue StandardError
          false
        end

        if exists
          active_count += 1
        else
          expired << person_id
        end
      end

      # Clean up expired entries from tracking set
      expired.each { |pid| redis.srem(skey, pid) } if expired.any?

      active_count
    end

    private

    def hold_key(offering_id, person_id)
      "#{KEY_PREFIX}:#{offering_id}:#{person_id}"
    end

    def set_key(offering_id)
      "#{SET_PREFIX}:#{offering_id}"
    end

    def redis
      REDIS
    end

    def redis_available?
      REDIS.present?
    rescue StandardError
      false
    end
  end
end
