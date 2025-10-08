
class AuditionRequest < ApplicationRecord
  belongs_to :call_to_audition
  belongs_to :person
  has_many :answers, dependent: :destroy

  enum :status, {
    unreviewed: 0,
    undecided: 1,
    passed: 2,
    accepted: 3
  }

  validates :video_url, presence: true, if: -> { call_to_audition&.audition_type == "video_upload" }

  def display_name
    person.name
  end

  def next
    call_to_audition.audition_requests.where("created_at > ?", created_at).order(created_at: :asc).first
  end

  def previous
    call_to_audition.audition_requests.where("created_at < ?", created_at).order(created_at: :desc).first
  end

  def scheduled_in_any?(audition_sessions)
    Audition.joins(:audition_session)
      .where(audition_request_id: id, audition_sessions: { id: audition_sessions.map(&:id) })
      .exists?
  end
end
