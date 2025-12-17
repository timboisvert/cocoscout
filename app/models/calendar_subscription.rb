# frozen_string_literal: true

class CalendarSubscription < ApplicationRecord
  belongs_to :person

  has_many :calendar_events, dependent: :destroy

  # Encryption for OAuth tokens
  encrypts :access_token_ciphertext, deterministic: false
  encrypts :refresh_token_ciphertext, deterministic: false

  # Aliases for cleaner access
  def access_token
    access_token_ciphertext
  end

  def access_token=(value)
    self.access_token_ciphertext = value
  end

  def refresh_token
    refresh_token_ciphertext
  end

  def refresh_token=(value)
    self.refresh_token_ciphertext = value
  end

  # Validations
  validates :provider, presence: true, inclusion: { in: %w[google ical] }
  validates :sync_scope, presence: true, inclusion: { in: %w[assigned talent_pool] }
  validates :person_id, uniqueness: { scope: :provider, message: "already has a subscription for this provider" }
  validates :ical_token, uniqueness: true, allow_nil: true

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :google, -> { where(provider: "google") }
  scope :ical, -> { where(provider: "ical") }

  # Callbacks
  before_create :generate_ical_token, if: -> { provider == "ical" }

  # Check if OAuth tokens are valid
  def token_valid?
    return true if provider == "ical"
    return false if access_token.blank?

    token_expires_at.nil? || token_expires_at > Time.current
  end

  def token_expired?
    !token_valid?
  end

  def needs_reauthorization?
    return false if provider == "ical"

    access_token.blank? || (refresh_token.blank? && token_expired?)
  end

  # Get the entities to sync for
  def sync_entity_ids
    return [] if sync_entities.blank?

    sync_entities.map { |e| { type: e["type"], id: e["id"] } }
  end

  # Check if a specific entity (Person or Group) should be synced
  def syncs_for?(entity)
    return false if sync_entities.blank?

    sync_entities.any? do |e|
      e["type"] == entity.class.name && e["id"] == entity.id
    end
  end

  # Get all shows that should be synced based on preferences
  def shows_to_sync
    return Show.none unless enabled?

    case sync_scope
    when "assigned"
      shows_for_assigned_entities
    when "talent_pool"
      shows_for_talent_pool_productions
    else
      Show.none
    end
  end

  # Get the iCal feed URL
  def ical_feed_url
    return nil unless provider == "ical" && ical_token.present?

    Rails.application.routes.url_helpers.calendar_feed_url(token: ical_token, host: Rails.application.config.action_mailer.default_url_options[:host])
  end

  # Mark as synced
  def mark_synced!
    update!(last_synced_at: Time.current, last_sync_error: nil)
  end

  # Mark sync error
  def mark_sync_error!(error_message)
    update!(last_sync_error: error_message)
  end

  private

  def generate_ical_token
    loop do
      self.ical_token = SecureRandom.urlsafe_base64(32)
      break unless CalendarSubscription.exists?(ical_token: ical_token)
    end
  end

  def shows_for_assigned_entities
    entity_conditions = sync_entities.map do |entity|
      "(show_person_role_assignments.assignable_type = '#{entity['type']}' AND show_person_role_assignments.assignable_id = #{entity['id']})"
    end

    return Show.none if entity_conditions.empty?

    Show.joins(:show_person_role_assignments)
        .where(entity_conditions.join(" OR "))
        .where("shows.date_and_time >= ?", Time.current.beginning_of_day)
        .distinct
  end

  def shows_for_talent_pool_productions
    # Get all productions where the person (or their groups) is in the talent pool
    person_talent_pool_ids = person.talent_pool_memberships.pluck(:talent_pool_id)
    group_talent_pool_ids = person.groups.joins(:talent_pool_memberships).pluck("talent_pool_memberships.talent_pool_id")

    all_talent_pool_ids = (person_talent_pool_ids + group_talent_pool_ids).uniq
    production_ids = TalentPool.where(id: all_talent_pool_ids).pluck(:production_id)

    Show.where(production_id: production_ids)
        .where("shows.date_and_time >= ?", Time.current.beginning_of_day)
  end
end
