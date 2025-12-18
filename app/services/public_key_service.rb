# frozen_string_literal: true

class PublicKeyService
  VALID_FORMAT_REGEX = /\A[a-z0-9][a-z0-9-]{2,29}\z/

  # Generate a unique public key from a base name (for new records)
  def self.generate(base_name)
    new(base_name).generate
  end

  # Validate a public key for manual URL changes (with optional cooldown/exclusions)
  def self.validate(proposed_key, entity_type: nil, exclude_entity: nil)
    new(proposed_key, entity_type: entity_type, exclude_entity: exclude_entity).validate
  end

  def initialize(key, entity_type: nil, exclude_entity: nil)
    @key = key&.strip&.downcase
    @entity_type = entity_type
    @exclude_entity = exclude_entity
  end

  # Generate an available key with auto-increment
  def generate
    base_key = @key.parameterize(separator: "")[0, 25] # Truncate to leave room for suffix
    key = base_key
    counter = 2

    while !format_valid?(key) || reserved?(key) || taken?(key)
      key = "#{base_key[0, 25]}-#{counter}"
      counter += 1
    end

    key
  end

  # Validate a proposed key for manual changes (returns hash with status and message)
  def validate
    # Validate format
    unless format_valid?(@key)
      return {
        available: false,
        message: "URL must be 3-30 characters: lowercase letters, numbers, and hyphens only"
      }
    end

    # Check cooldown (only for entity type changes, not new registrations)
    if @exclude_entity
      if @exclude_entity.public_key_changed_at && @exclude_entity.public_key_changed_at > cooldown_days.ago
        return {
          available: false,
          message: "You changed your public URL too recently."
        }
      end

      # Check if same as current
      if @key == @exclude_entity.public_key
        return {
          available: false,
          message: "This is already your current URL"
        }
      end
    end

    # Check reserved
    if reserved?(@key)
      return {
        available: false,
        message: "This URL is reserved for CocoScout system pages"
      }
    end

    # Check if taken
    if taken?(@key, exclude_entity: @exclude_entity)
      return {
        available: false,
        message: "This URL is already taken"
      }
    end

    # Available!
    { available: true, message: "This URL is available!" }
  end

  private

  def format_valid?(key)
    key =~ VALID_FORMAT_REGEX
  end

  def reserved?(key)
    reserved_keys = YAML.safe_load_file(
      Rails.root.join("config", "reserved_public_keys.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    )
    reserved_keys.include?(key)
  end

  def taken?(key, exclude_entity: nil)
    person_query = Person.where(public_key: key)
    group_query = Group.where(public_key: key)
    production_query = Production.where(public_key: key)

    person_query = person_query.where.not(id: exclude_entity.id) if @entity_type == :person && exclude_entity
    group_query = group_query.where.not(id: exclude_entity.id) if @entity_type == :group && exclude_entity
    production_query = production_query.where.not(id: exclude_entity.id) if @entity_type == :production && exclude_entity

    person_query.exists? || group_query.exists? || production_query.exists?
  end

  def cooldown_days
    settings = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))
    settings["url_change_cooldown_days"].days
  end
end
