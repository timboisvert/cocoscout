class CallToAudition < ApplicationRecord
  has_many :audition_requests, dependent: :destroy
  has_many :audition_sessions, dependent: :destroy
  has_many :questions, as: :questionable, dependent: :destroy
  has_many :email_groups, dependent: :destroy
  has_many :audition_email_assignments, dependent: :destroy

  has_rich_text :header_text
  has_rich_text :video_field_text
  has_rich_text :success_text

  belongs_to :production

  validates :opens_at, presence: true
  validates :closes_at, presence: true
  validate :form_must_be_reviewed_before_opening
  validate :closes_at_after_opens_at

  enum :audition_type, {
    in_person: "in_person",
    video_upload: "video_upload"
  }

  # Serialize availability_event_types as an array
  serialize :availability_event_types, coder: JSON

  def production_name
    self.production.name
  end

  def counts
    {
      unreviewed: self.audition_requests.where(status: :unreviewed).count,
      undecided: self.audition_requests.where(status: :undecided).count,
      passed: self.audition_requests.where(status: :passed).count,
      accepted: self.audition_requests.where(status: :accepted).count
    }
  end

  def timeline_status
    if self.opens_at > Time.current
      :upcoming
    elsif self.closes_at <= Time.current
      :closed
    else
      :open
    end
  end

  def respond_url
    if Rails.env.development?
      "http://localhost:3000/a/#{self.token}"
    else
      "https://www.cocoscout.com/a/#{self.token}"
    end
  end

  def form_must_be_reviewed_before_opening
    # If the audition has already started and form isn't reviewed, it should be hidden/inactive
    # (same as if it wasn't opened yet). This doesn't prevent saving the checkbox value though.
    # That's a display/UX concern, not a validation concern.
  end

  def closes_at_after_opens_at
    if opens_at.present? && closes_at.present? && closes_at <= opens_at
      errors.add(:closes_at, "must be after the opening date and time")
    end
  end

  def opening_soon?
    opens_at.present? && opens_at <= 7.days.from_now && opens_at > Time.current
  end

  def opening_soon_and_not_reviewed?
    opening_soon? && !form_reviewed
  end
end
