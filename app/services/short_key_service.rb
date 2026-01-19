# frozen_string_literal: true

# ShortKeyService provides centralized management for short URL keys.
#
# These keys are used for:
# - /a/<key> - Audition cycle response URLs (AuditionCycle.token)
# - /s/<key> - Sign-up form short URLs (SignUpForm.short_code)
#
# Keys are "sacred" - once assigned, they should last forever.
# This service ensures uniqueness across both key namespaces and provides
# monitoring capabilities for capacity planning.
#
class ShortKeyService
  # Character set: A-Z, 0-9 (36 characters)
  # With 5 characters: 36^5 = 60,466,176 possible combinations per type
  DEFAULT_KEY_LENGTH = 5
  CHARSET = ("A".."Z").to_a + ("0".."9").to_a
  MAX_RETRIES = 100

  KEY_TYPES = {
    audition: {
      model: "AuditionCycle",
      column: :token,
      path_prefix: "/a/"
    },
    signup: {
      model: "SignUpForm",
      column: :short_code,
      path_prefix: "/s/"
    }
  }.freeze

  class KeyGenerationError < StandardError; end

  class << self
    # Generate a unique key for the given type
    # @param type [Symbol] :audition or :signup
    # @param length [Integer] key length (default: 5)
    # @return [String] unique uppercase alphanumeric key
    # @raise [KeyGenerationError] if unable to generate unique key after MAX_RETRIES
    def generate(type:, length: DEFAULT_KEY_LENGTH)
      validate_type!(type)

      retries = 0
      loop do
        key = generate_random_key(length)

        unless key_exists?(type, key)
          return key
        end

        retries += 1
        if retries >= MAX_RETRIES
          raise KeyGenerationError, "Unable to generate unique #{type} key after #{MAX_RETRIES} attempts. " \
                                    "Consider increasing key length or reviewing capacity."
        end
      end
    end

    # Generate and assign a key to a record
    # @param record [ActiveRecord::Base] the record to assign the key to
    # @param type [Symbol] :audition or :signup
    # @param length [Integer] key length (default: 5)
    # @return [String] the assigned key
    def generate_for!(record, type:, length: DEFAULT_KEY_LENGTH)
      config = KEY_TYPES[type]
      column = config[:column]

      # Don't regenerate if already present
      return record.send(column) if record.send(column).present?

      key = generate(type: type, length: length)
      record.update!(column => key)
      key
    end

    # Look up a record by its short key
    # @param type [Symbol] :audition or :signup
    # @param key [String] the key to look up
    # @return [ActiveRecord::Base, nil] the record or nil if not found
    def find_by_key(type:, key:)
      validate_type!(type)
      config = KEY_TYPES[type]
      model_class(type).find_by(config[:column] => key&.upcase)
    end

    # Get statistics for capacity monitoring
    # @return [Hash] statistics for all key types
    def statistics
      stats = {}

      KEY_TYPES.each do |type, config|
        total_possible = capacity_for_length(DEFAULT_KEY_LENGTH)
        used_count = model_class(type).where.not(config[:column] => nil).count
        available = total_possible - used_count
        usage_percentage = (used_count.to_f / total_possible * 100).round(4)

        stats[type] = {
          total_capacity: total_possible,
          used: used_count,
          available: available,
          usage_percentage: usage_percentage,
          path_prefix: config[:path_prefix],
          model: config[:model],
          column: config[:column],
          key_length: DEFAULT_KEY_LENGTH,
          charset_size: CHARSET.size
        }
      end

      # Combined stats
      stats[:combined] = {
        total_used: stats.values.reject { |v| v.is_a?(Hash) && v[:total_capacity] }.sum { |v| v[:used] rescue 0 },
        audition_used: stats[:audition][:used],
        signup_used: stats[:signup][:used]
      }

      # Fix combined stats calculation
      stats[:combined] = {
        total_used: stats[:audition][:used] + stats[:signup][:used],
        audition_used: stats[:audition][:used],
        signup_used: stats[:signup][:used]
      }

      stats
    end

    # Get all keys with their associated records for monitoring
    # @param type [Symbol, nil] :audition, :signup, or nil for all
    # @return [Array<Hash>] array of key info hashes
    def all_keys(type: nil)
      types = type ? [ type ] : KEY_TYPES.keys

      keys = []
      types.each do |t|
        validate_type!(t)
        keys.concat(keys_for_type(t))
      end

      keys.sort_by { |k| k[:created_at] }.reverse
    end

    # Calculate total possible keys for a given length
    # @param length [Integer] key length
    # @return [Integer] total possible combinations
    def capacity_for_length(length)
      CHARSET.size**length
    end

    # Health check for key capacity
    # @return [Hash] health status and warnings
    def health_check
      stats = statistics
      warnings = []

      KEY_TYPES.each_key do |type|
        type_stats = stats[type]
        if type_stats[:usage_percentage] > 50
          warnings << "#{type} keys are at #{type_stats[:usage_percentage]}% capacity"
        end
      end

      {
        healthy: warnings.empty?,
        warnings: warnings,
        statistics: stats
      }
    end

    private

    def validate_type!(type)
      unless KEY_TYPES.key?(type)
        raise ArgumentError, "Invalid key type: #{type}. Must be one of: #{KEY_TYPES.keys.join(', ')}"
      end
    end

    def generate_random_key(length)
      Array.new(length) { CHARSET.sample }.join
    end

    def key_exists?(type, key)
      config = KEY_TYPES[type]
      model_class(type).exists?(config[:column] => key)
    end

    def model_class(type)
      KEY_TYPES[type][:model].constantize
    end

    def keys_for_type(type)
      config = KEY_TYPES[type]
      column = config[:column]
      model = model_class(type)

      records = model.where.not(column => nil)
                     .includes(type == :audition ? { production: :organization } : { production: :organization })

      records.map do |record|
        key_info_for_record(record, type, config, column)
      end
    end

    def key_info_for_record(record, type, config, column)
      key = record.send(column)
      production = record.production

      base_info = {
        key: key,
        type: type,
        path: "#{config[:path_prefix]}#{key}",
        created_at: record.created_at,
        record_id: record.id,
        production_id: production&.id,
        production_name: production&.name,
        organization_id: production&.organization&.id,
        organization_name: production&.organization&.name
      }

      # Add type-specific info
      case type
      when :audition
        # AuditionCycle doesn't have a name, use production name with status
        cycle_name = "#{production&.name} Auditions"
        cycle_name += " (#{record.opens_at&.strftime('%b %Y')})" if record.opens_at
        base_info.merge(
          name: cycle_name,
          active: record.active,
          status: record.active ? "active" : "inactive"
        )
      when :signup
        base_info.merge(
          name: record.name,
          active: record.active,
          status: record.active ? "active" : "inactive"
        )
      else
        base_info
      end
    end
  end
end
