class CallToAudition < ApplicationRecord
  has_many :audition_requests, dependent: :destroy
  has_many :audition_sessions, dependent: :destroy
  has_many :questions, as: :questionable, dependent: :destroy

  has_rich_text :header_text
  has_rich_text :video_field_text
  has_rich_text :success_text

  belongs_to :production

  validates :opens_at, presence: true
  validates :closes_at, presence: true

  enum :audition_type, {
    in_person: "in_person",
    video_upload: "video_upload"
  }

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
end
