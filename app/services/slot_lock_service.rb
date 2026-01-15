# frozen_string_literal: true

# Manages temporary locks on sign-up slots using Redis.
# When a user clicks to register for a slot, they get a temporary exclusive lock.
# This prevents race conditions where multiple users try to register for the same slot.
#
# Usage:
#   SlotLockService.acquire(slot_id, session_id, duration: 30) # => { success: true, expires_in: 30 }
#   SlotLockService.release(slot_id, session_id) # => true
#   SlotLockService.locked?(slot_id)             # => true/false
#   SlotLockService.lock_info(slot_id)           # => { locked: true, locked_by_me: false, expires_in: 25 }
#
class SlotLockService
  DEFAULT_LOCK_DURATION = 30.seconds
  KEY_PREFIX = "slot_lock"

  class << self
    # Attempt to acquire a lock on a slot
    # Returns hash with :success, :expires_in, :error
    def acquire(slot_id, session_id, duration: DEFAULT_LOCK_DURATION)
      return { success: false, error: "Redis not available" } unless redis_available?

      key = lock_key(slot_id)
      lock_duration = duration.to_i

      # Use SET with NX (only if not exists) and EX (expiry)
      # This is atomic and race-condition safe
      result = redis.set(key, session_id, nx: true, ex: lock_duration)

      if result
        { success: true, expires_in: lock_duration }
      else
        # Lock exists - check if it's ours (user refreshed page, etc.)
        current_holder = redis.get(key)
        if current_holder == session_id
          # It's our lock - extend it
          redis.expire(key, lock_duration)
          { success: true, expires_in: lock_duration, extended: true }
        else
          # Someone else has the lock
          ttl = redis.ttl(key)
          { success: false, error: "Slot is being held by another user", expires_in: ttl > 0 ? ttl : nil }
        end
      end
    end

    # Release a lock (only if we own it)
    def release(slot_id, session_id)
      return false unless redis_available?

      key = lock_key(slot_id)
      current_holder = redis.get(key)

      if current_holder == session_id
        redis.del(key)
        true
      else
        false
      end
    end

    # Check if a slot is currently locked
    def locked?(slot_id)
      return false unless redis_available?
      redis.exists?(lock_key(slot_id))
    end

    # Get lock info for a slot (useful for UI)
    def lock_info(slot_id, session_id = nil)
      return { locked: false, redis_available: false } unless redis_available?

      key = lock_key(slot_id)
      current_holder = redis.get(key)

      if current_holder.nil?
        { locked: false }
      else
        ttl = redis.ttl(key)
        {
          locked: true,
          locked_by_me: session_id.present? && current_holder == session_id,
          expires_in: ttl > 0 ? ttl : nil
        }
      end
    end

    # Get lock info for multiple slots at once (efficient batch check)
    # Uses pipelining for Redis Cluster compatibility (mget fails with CROSSSLOT error)
    def bulk_lock_info(slot_ids, session_id = nil)
      return slot_ids.index_with { { locked: false, redis_available: false } } unless redis_available?
      return {} if slot_ids.empty?

      # Use pipelining instead of mget to avoid CROSSSLOT errors in Redis Cluster
      # Each key is fetched individually but in a single round trip
      holders = {}
      redis.pipelined do |pipeline|
        slot_ids.each do |slot_id|
          holders[slot_id] = pipeline.get(lock_key(slot_id))
        end
      end

      slot_ids.to_h do |slot_id|
        holder = holders[slot_id].value rescue nil
        info = if holder.nil?
          { locked: false }
        else
          ttl = redis.ttl(lock_key(slot_id))
          {
            locked: true,
            locked_by_me: session_id.present? && holder == session_id,
            expires_in: ttl > 0 ? ttl : nil
          }
        end
        [ slot_id, info ]
      end
    end

    # Release all locks held by a session (cleanup on logout, etc.)
    def release_all_for_session(session_id)
      return unless redis_available?

      # Scan for all locks and release ones matching this session
      cursor = "0"
      loop do
        cursor, keys = redis.scan(cursor, match: "#{KEY_PREFIX}:*")
        keys.each do |key|
          redis.del(key) if redis.get(key) == session_id
        end
        break if cursor == "0"
      end
    end

    private

    def lock_key(slot_id)
      "#{KEY_PREFIX}:#{slot_id}"
    end

    def redis
      REDIS
    end

    def redis_available?
      REDIS.present?
    rescue
      false
    end
  end
end
