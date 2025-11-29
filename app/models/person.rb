class Person < ApplicationRecord
  has_many :socials, as: :sociable, dependent: :destroy
  accepts_nested_attributes_for :socials, allow_destroy: true

  has_many :audition_requests, as: :requestable, dependent: :destroy
  has_many :auditions

  has_many :talent_pool_memberships, as: :member, dependent: :destroy
  has_many :talent_pools, through: :talent_pool_memberships
  has_and_belongs_to_many :organizations

  has_many :cast_assignment_stages, dependent: :destroy

  has_many :questionnaire_invitations, as: :invitee, dependent: :destroy
  has_many :invited_questionnaires, through: :questionnaire_invitations, source: :questionnaire
  has_many :questionnaire_responses, as: :respondent, dependent: :destroy

  has_many :show_person_role_assignments, as: :assignable, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments
  has_many :roles, through: :show_person_role_assignments

  has_many :show_availabilities, as: :available_entity, dependent: :destroy
  has_many :available_shows, through: :show_availabilities, source: :show

  has_many :group_memberships, dependent: :destroy
  has_many :groups, through: :group_memberships

  # Profile system associations
  has_many :profile_headshots, as: :profileable, dependent: :destroy
  has_many :profile_resumes, as: :profileable, dependent: :destroy
  has_many :profile_videos, as: :profileable, dependent: :destroy
  has_many :performance_sections, as: :profileable, dependent: :destroy
  has_many :performance_credits, as: :profileable, dependent: :destroy
  has_many :training_credits, dependent: :destroy
  has_many :profile_skills, as: :profileable, dependent: :destroy

  # Accept nested attributes for profile system
  accepts_nested_attributes_for :profile_headshots, allow_destroy: true
  accepts_nested_attributes_for :profile_resumes, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :profile_videos, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :performance_sections, allow_destroy: true
  accepts_nested_attributes_for :performance_credits, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :training_credits, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :profile_skills, allow_destroy: true, reject_if: :all_blank

  has_one_attached :resume, dependent: :purge_later
  has_one_attached :headshot, dependent: :purge_later do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 100, 100 ], preprocessed: true
  end

  belongs_to :user, optional: true

  # Validations
  validates :name, presence: true
  validates :email, presence: true
  validates :public_key, uniqueness: true, allow_nil: true
  validates :public_key, format: { with: /\A[a-z0-9][a-z0-9\-]{2,29}\z/, message: "must be 3-30 characters, lowercase letters, numbers, and hyphens only" }, allow_blank: true
  validate :public_key_not_reserved
  validate :resume_content_type
  validate :headshot_content_type
  validate :email_change_frequency
  validate :public_key_change_frequency

  # Callbacks
  before_validation :generate_public_key, on: :create
  before_validation :downcase_public_key
  before_save :track_email_change
  before_save :track_public_key_change

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

  def safe_resume_preview(options = {})
    return nil unless resume.attached?

    # For image files (JPEG, PNG), display directly with variant
    if resume.content_type.start_with?("image/")
      return resume.variant(options)
    end

    # For other files (PDF), generate preview
    return nil unless resume.previewable?
    resume.preview(options)
  rescue ActiveStorage::PreviewError, ActiveStorage::InvariableError => e
    Rails.logger.error("Failed to generate preview for #{name}'s resume: #{e.message}")
    nil
  end

  def safe_headshot_variant(variant_name)
    hs = headshot
    return nil unless hs&.attached?
    hs.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for #{name}'s headshot: #{e.message}")
    nil
  end

  def has_person_role_assignment_for_show?(show)
    show_person_role_assignments.exists?(show: show)
  end

  # Returns all questionnaires this person is invited to, either directly or through group membership
  def all_invited_questionnaires
    # Get questionnaires where person is directly invited
    direct_questionnaires = invited_questionnaires

    # Get questionnaires where person's groups are invited
    group_questionnaire_ids = QuestionnaireInvitation
      .where(invitee_type: "Group", invitee_id: groups.pluck(:id))
      .pluck(:questionnaire_id)

    group_questionnaires = Questionnaire.where(id: group_questionnaire_ids)

    # Combine and return unique questionnaires
    Questionnaire.where(id: (direct_questionnaires.pluck(:id) + group_questionnaires.pluck(:id)).uniq)
  end

  # Returns the next show for a given production that this person has a role assignment in
  def next_show_for_production_that_im_cast_in(production)
    shows
      .joins(:show_person_role_assignments)
      .where(production: production, show_person_role_assignments: { assignable_type: "Person", assignable_id: id })
      .where("date_and_time >= ?", Time.current)
      .where(canceled: false)
      .order(:date_and_time)
      .first
  end

  # Returns the next event (show, rehearsal, or meeting) for a given production, regardless of cast status
  def next_event_for_production(production)
    Show
      .where(production: production, canceled: false)
      .where("date_and_time >= ?", Time.current)
      .order(:date_and_time)
      .first
  end

  # Profile system helper methods
  def primary_headshot
    profile_headshots.find_by(is_primary: true) || profile_headshots.first
  end

  # Override headshot to return the primary headshot's image when profile_headshots exist
  def headshot
    primary = primary_headshot
    if primary&.image&.attached?
      primary.image
    else
      # Call the original has_one_attached method
      super()
    end
  end

  def display_headshots
    if profile_headshots.any?
      profile_headshots
    elsif headshot.attached?
      [ OpenStruct.new(image: headshot, category: "Primary", is_primary: true, position: 0) ]
    else
      []
    end
  end

  def display_resume
    resume # Existing ActiveStorage attachment
  end

  def visibility_settings
    @visibility_settings ||= begin
      settings = profile_visibility_settings.presence || "{}"
      settings = JSON.parse(settings) if settings.is_a?(String)
      settings.with_indifferent_access
    rescue JSON::ParserError
      {}
    end
  end

  def performance_credits_visible?
    read_attribute(:performance_credits_visible)
  end

  def training_credits_visible?
    read_attribute(:training_credits_visible)
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

    base_key = name.parameterize(separator: "")
    key = base_key
    counter = 2

    while Person.where(public_key: key).exists? || Group.where(public_key: key).exists?
      key = "#{base_key}-#{counter}"
      counter += 1
    end

    self.public_key = key
  end

  def downcase_public_key
    self.public_key = public_key.downcase if public_key.present?
  end

  def public_key_not_reserved
    return if public_key.blank?

    reserved = YAML.safe_load_file(
      Rails.root.join("config", "reserved_public_keys.yml"),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true
    )
    if reserved.include?(public_key)
      errors.add(:public_key, "is reserved for CocoScout system pages")
    end
  end

  def resume_content_type
    if resume.attached? && !resume.content_type.in?(%w[application/pdf image/jpeg image/png])
      errors.add(:resume, "Resume must be a PDF, JPEG, or PNG file")
    end
  end

  def headshot_content_type
    if headshot.attached? && !headshot.content_type.in?(%w[image/jpeg image/jpg image/png])
      errors.add(:headshot, "Headshot must be a JPEG, JPG, or PNG file")
    end
  end

  def email_change_frequency
    return if email_was.nil? || email == email_was # No change or new record
    return if last_email_changed_at.nil? # First time changing

    cooldown_days = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))["email_change_cooldown_days"]
    days_since_last_change = (Time.current - last_email_changed_at) / 1.day
    if days_since_last_change < cooldown_days
      days_remaining = (cooldown_days - days_since_last_change).ceil
      errors.add(:email, "was changed too recently. Please wait #{days_remaining} more day#{'s' if days_remaining != 1} before changing it again.")
    end
  end

  def public_key_change_frequency
    return if public_key_was.nil? || public_key == public_key_was # No change or new record
    return if public_key_changed_at.nil? # First time changing

    cooldown_days = YAML.load_file(Rails.root.join("config", "profile_settings.yml"))["url_change_cooldown_days"]
    days_since_last_change = (Time.current - public_key_changed_at) / 1.day
    if days_since_last_change < cooldown_days
      errors.add(:public_key, "was changed too recently.")
    end
  end

  def track_email_change
    if email_changed? && !new_record?
      self.last_email_changed_at = Time.current
    end
  end

  def track_public_key_change
    if public_key_changed? && !new_record?
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
  end
end
