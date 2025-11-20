class AuditionRequest < ApplicationRecord
  belongs_to :audition_cycle
  belongs_to :requestable, polymorphic: true
  has_many :answers, dependent: :destroy

  enum :status, {
    unreviewed: 0,
    undecided: 1,
    passed: 2,
    accepted: 3
  }

  validates :video_url, presence: true, if: -> { audition_cycle&.audition_type == "video_upload" }

  # Helper method for backward compatibility - auditions are always for individual people
  def person
    requestable if requestable_type == "Person"
  end

  def display_name
    requestable.name
  end

  def next
    audition_cycle.audition_requests.where("created_at > ?", created_at).order(created_at: :asc).first
  end

  def previous
    audition_cycle.audition_requests.where("created_at < ?", created_at).order(created_at: :desc).first
  end

  def scheduled_in_any?(audition_sessions)
    Audition.joins(:audition_session)
      .where(audition_request_id: id, audition_sessions: { id: audition_sessions.map(&:id) })
      .exists?
  end
end
