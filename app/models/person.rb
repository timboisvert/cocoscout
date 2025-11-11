class Person < ApplicationRecord
  has_many :socials, dependent: :destroy
  accepts_nested_attributes_for :socials, allow_destroy: true

  has_many :audition_requests, dependent: :destroy
  has_many :auditions

  has_and_belongs_to_many :casts
  has_and_belongs_to_many :production_companies

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments
  has_many :roles, through: :show_person_role_assignments

  has_many :show_availabilities, dependent: :destroy
  has_many :available_shows, through: :show_availabilities, source: :show

  has_one_attached :resume, dependent: :purge_later
  has_one_attached :headshot, dependent: :purge_later do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 100, 100 ], preprocessed: true
  end

  belongs_to :user, optional: true

  # Validations
  validates :name, presence: true
  validates :email, presence: true
  validate :resume_content_type
  validate :headshot_content_type

  def initials
    return "" if name.blank?
    name.split.map { |word| word[0] }.join.upcase
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
    return nil unless headshot.attached?
    headshot.variant(variant_name)
  rescue ActiveStorage::InvariableError, ActiveStorage::FileNotFoundError => e
    Rails.logger.error("Failed to generate variant for #{name}'s headshot: #{e.message}")
    nil
  end

  def has_person_role_assignment_for_show?(show)
    show_person_role_assignments.exists?(show: show)
  end

  # Returns the next show for a given production that this person has a role assignment in
  def next_show_for_production_that_im_cast_in(production)
    shows
      .joins(:show_person_role_assignments)
      .where(production: production, show_person_role_assignments: { person_id: id })
      .where("date_and_time >= ?", Time.current, canceled: false)
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

  private

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
