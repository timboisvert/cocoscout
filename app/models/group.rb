class Group < ApplicationRecord
  has_many :group_memberships, dependent: :destroy
  has_many :members, through: :group_memberships, source: :person
  has_many :socials, as: :sociable, dependent: :destroy
  accepts_nested_attributes_for :socials, allow_destroy: true

  has_many :audition_requests, as: :requestable, dependent: :destroy
  has_many :talent_pool_memberships, as: :member, dependent: :destroy
  has_many :talent_pools, through: :talent_pool_memberships

  has_many :questionnaire_invitations, as: :invitee, dependent: :destroy
  has_many :invited_questionnaires, through: :questionnaire_invitations, source: :questionnaire
  has_many :questionnaire_responses, as: :respondent, dependent: :destroy

  has_many :show_availabilities, as: :available_entity, dependent: :destroy
  has_many :available_shows, through: :show_availabilities, source: :show

  has_one_attached :resume, dependent: :purge_later
  has_one_attached :headshot, dependent: :purge_later do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 100, 100 ], preprocessed: true
  end

  # Validations
  validates :name, presence: true
  validates :email, presence: true
  validates :public_key, presence: true, uniqueness: true
  validates :public_key, format: { with: /\A[a-z0-9][a-z0-9\-]{2,29}\z/, message: "must be 3-30 characters, lowercase letters, numbers, and hyphens only" }, allow_blank: true
  validate :public_key_not_reserved
  validate :resume_content_type
  validate :headshot_content_type

  # Callbacks
  before_validation :generate_public_key, on: :create
  before_validation :downcase_public_key

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

  def safe_resume_preview(options = {})
    return nil unless resume.attached?

    if resume.content_type.start_with?("image/")
      return resume.variant(options)
    end

    return nil unless resume.previewable?
    resume.preview(options)
  rescue ActiveStorage::PreviewError, ActiveStorage::InvariableError => e
    Rails.logger.error("Failed to generate preview for #{name}'s resume: #{e.message}")
    nil
  end

  def safe_headshot_variant(variant_name)
    return nil unless headshot.attached?
    headshot.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for #{name}'s headshot: #{e.message}")
    nil
  end

  private

  def generate_public_key
    return if public_key.present?

    base_key = name.parameterize
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
    reserved = %w[admin api manage my about help contact support settings login logout signup privacy terms groups people search directory]
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
end
