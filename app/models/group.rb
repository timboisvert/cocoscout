# frozen_string_literal: true

class Group < ApplicationRecord
  include CacheInvalidation
  invalidates_cache :group_card, :group_profile

  has_many :group_memberships, dependent: :destroy
  has_many :group_invitations, dependent: :destroy
  has_many :members, through: :group_memberships, source: :person
  has_many :socials, as: :sociable, dependent: :destroy
  accepts_nested_attributes_for :socials, allow_destroy: true

  has_and_belongs_to_many :organizations

  has_many :audition_requests, as: :requestable, dependent: :destroy
  has_many :talent_pool_memberships, as: :member, dependent: :destroy
  has_many :talent_pools, through: :talent_pool_memberships

  has_many :questionnaire_invitations, as: :invitee, dependent: :destroy
  has_many :invited_questionnaires, through: :questionnaire_invitations, source: :questionnaire
  has_many :questionnaire_responses, as: :respondent, dependent: :destroy

  has_many :show_availabilities, as: :available_entity, dependent: :destroy
  has_many :available_shows, through: :show_availabilities, source: :show

  # Casting system associations
  has_many :show_person_role_assignments, as: :assignable, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments
  has_many :roles, through: :show_person_role_assignments
  has_many :role_eligibilities, as: :member, dependent: :destroy

  # Shoutout associations
  has_many :received_shoutouts, as: :shoutee, class_name: "Shoutout", dependent: :destroy

  # Profile system associations
  has_many :profile_headshots, as: :profileable, dependent: :destroy
  has_many :profile_videos, as: :profileable, dependent: :destroy
  has_many :performance_sections, as: :profileable, dependent: :destroy
  has_many :performance_credits, as: :profileable, dependent: :destroy
  has_many :profile_skills, as: :profileable, dependent: :destroy
  has_many :profile_resumes, as: :profileable, dependent: :destroy

  # Accept nested attributes for profile system
  accepts_nested_attributes_for :profile_headshots, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :profile_videos, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :performance_sections, allow_destroy: true
  accepts_nested_attributes_for :performance_credits, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :profile_skills, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :profile_resumes, allow_destroy: true, reject_if: :all_blank

  # Rich text for producer notes about this group
  has_rich_text :producer_notes

  # Validations
  validates :name, presence: true
  validates :email, presence: true
  validates :public_key, presence: true, uniqueness: true
  validates :public_key,
            format: { with: /\A[a-z0-9][a-z0-9-]{2,29}\z/, message: "must be 3-30 characters, lowercase letters, numbers, and hyphens only" }, allow_blank: true
  validate :public_key_not_reserved

  # Callbacks
  before_validation :generate_public_key, on: :create
  before_validation :downcase_public_key
  before_save :track_public_key_change

  # Scopes
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def archive!
    update(archived_at: Time.current)
  end

  def unarchive!
    update(archived_at: nil)
  end

  def initials
    return "" if name.blank?

    name.split.map { |word| word[0] }.join.upcase
  end

  def update_public_key(new_key)
    return false if new_key == public_key

    old_keys_array = old_keys.present? ? JSON.parse(old_keys) : []
    old_keys_array << public_key unless old_keys_array.include?(public_key)

    self.public_key = new_key
    self.old_keys = old_keys_array.to_json
    save
  end

  # Profile system helper methods
  def primary_headshot
    # Use in-memory filtering to leverage preloaded associations
    # instead of find_by which bypasses eager loading
    profile_headshots.find(&:is_primary) || profile_headshots.first
  end

  def headshot
    primary_headshot&.image
  end

  def safe_headshot_variant(variant_name)
    hs = headshot
    return nil unless hs&.attached?

    hs.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for #{name}'s headshot: #{e.message}")
    nil
  end

  # Cached card data for display in lists (talent pools, directories, etc.)
  # Invalidated automatically when group is updated via CacheInvalidation concern
  def cached_card_data
    Rails.cache.fetch(cache_key_for(:group_card), expires_in: 1.hour) do
      {
        id: id,
        name: name,
        initials: initials,
        email: email,
        has_headshot: headshot&.attached?,
        member_count: members.count,
        updated_at: updated_at
      }
    end
  end

  # Cached profile data for profile views
  # Invalidated automatically when group is updated via CacheInvalidation concern
  def cached_profile_data
    Rails.cache.fetch(cache_key_for(:group_profile), expires_in: 1.hour) do
      {
        id: id,
        name: name,
        initials: initials,
        email: email,
        bio: bio,
        public_key: public_key,
        has_headshot: headshot&.attached?,
        headshot_count: profile_headshots.count,
        resume_count: profile_resumes.count,
        video_count: profile_videos.count,
        skills_count: profile_skills.count,
        member_count: members.count,
        updated_at: updated_at
      }
    end
  end

  def safe_resume_preview(options = {})
    primary_resume = profile_resumes.find_by(is_primary: true) || profile_resumes.first
    return nil unless primary_resume&.file&.attached?

    # For image files (JPEG, PNG), display directly with variant
    return primary_resume.file.variant(options) if primary_resume.file.content_type.start_with?("image/")

    # For other files (PDF), generate preview
    return nil unless primary_resume.file.previewable?

    primary_resume.file.preview(options)
  rescue ActiveStorage::PreviewError, ActiveStorage::InvariableError => e
    Rails.logger.error("Failed to generate preview for #{name}'s resume: #{e.message}")
    nil
  end

  def display_headshots
    profile_headshots
  end

  def display_resume
    profile_resumes.find_by(is_primary: true) || profile_resumes.first
  end

  def visibility_settings
    @visibility_settings ||= begin
      settings = profile_visibility_settings.presence || "{}"
      settings = JSON.parse(settings) if settings.is_a?(String)
      settings.with_indifferent_access
    end
  end

  # Casting system helper methods
  def has_person_role_assignment_for_show?(show)
    show_person_role_assignments.exists?(show: show)
  end

  def performance_credits_visible?
    read_attribute(:performance_credits_visible)
  end

  def profile_skills_visible?
    read_attribute(:profile_skills_visible)
  end

  def videos_visible?
    read_attribute(:videos_visible)
  end

  def headshots_visible?
    read_attribute(:headshots_visible)
  end

  def resumes_visible?
    read_attribute(:resumes_visible)
  end

  def social_media_visible?
    read_attribute(:social_media_visible)
  end

  def bio_visible?
    read_attribute(:bio_visible)
  end

  # Venmo payout methods
  VENMO_IDENTIFIER_TYPES = %w[PHONE EMAIL USER_HANDLE].freeze

  validates :venmo_identifier_type, inclusion: { in: VENMO_IDENTIFIER_TYPES }, allow_nil: true
  validate :venmo_identifier_format, if: -> { venmo_identifier.present? && venmo_identifier_type.present? }

  def venmo_configured?
    venmo_identifier.present? && venmo_identifier_type.present?
  end

  def venmo_ready_for_payouts?
    venmo_configured?
  end

  def needs_venmo_setup?
    !venmo_configured?
  end

  def venmo_status_label
    venmo_configured? ? "Connected" : "Not Set Up"
  end

  def venmo_status_color
    venmo_configured? ? "green" : "gray"
  end

  def formatted_venmo_identifier
    return nil unless venmo_identifier.present?

    case venmo_identifier_type
    when "PHONE"
      digits = venmo_identifier.gsub(/\D/, "")
      return venmo_identifier unless digits.length == 10

      "(#{digits[0..2]}) #{digits[3..5]}-#{digits[6..9]}"
    when "EMAIL"
      venmo_identifier
    when "USER_HANDLE"
      "@#{venmo_identifier.delete('@')}"
    else
      venmo_identifier
    end
  end

  # Virtual attribute for inverted contact info visibility logic
  def show_contact_info
    !hide_contact_info
  end

  def show_contact_info=(value)
    self.hide_contact_info = !ActiveModel::Type::Boolean.new.cast(value)
  end

  private

  def generate_public_key
    return if public_key.present?

    self.public_key = PublicKeyService.generate(name)
  end

  def downcase_public_key
    self.public_key = public_key.downcase if public_key.present?
  end

  def track_public_key_change
    return unless public_key_changed? && !new_record?

    # Store the old key
    old_keys_array = old_keys.present? ? JSON.parse(old_keys) : []
    old_key = public_key_was

    # Add the old key to the array if it's not already there and not nil
    if old_key.present? && !old_keys_array.include?(old_key)
      old_keys_array << old_key
      self.old_keys = old_keys_array.to_json
    end

    # Update the timestamp
    self.public_key_changed_at = Time.current
  end

  def public_key_not_reserved
    reserved = YAML.safe_load_file(
      Rails.root.join("config", "reserved_public_keys.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    )
    return unless reserved.include?(public_key)

    errors.add(:public_key, "is reserved for CocoScout system pages")
  end

  def venmo_identifier_format
    case venmo_identifier_type
    when "PHONE"
      digits = venmo_identifier.gsub(/\D/, "")
      errors.add(:venmo_identifier, "must be a valid 10-digit US phone number") unless digits.length == 10
    when "EMAIL"
      errors.add(:venmo_identifier, "must be a valid email address") unless venmo_identifier.match?(URI::MailTo::EMAIL_REGEXP)
    when "USER_HANDLE"
      handle = venmo_identifier.delete("@")
      errors.add(:venmo_identifier, "must be a valid Venmo username (5-30 characters)") unless handle.match?(/\A[a-zA-Z0-9-]{5,30}\z/)
    end
  end
end
