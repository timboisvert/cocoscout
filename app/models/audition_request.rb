# frozen_string_literal: true

class AuditionRequest < ApplicationRecord
  belongs_to :audition_cycle
  belongs_to :requestable, polymorphic: true
  has_many :answers, dependent: :destroy
  has_many :auditions, dependent: :destroy
  has_many :audition_session_availabilities, as: :available_entity, dependent: :destroy

  enum :status, {
    unreviewed: 0,
    undecided: 1,
    passed: 2,
    accepted: 3
  }

  validates :video_url, presence: true, if: -> { audition_cycle&.audition_type == "video_upload" }

  # Cache invalidation - when status changes, invalidate the counts cache
  after_commit :invalidate_cycle_caches, on: %i[create update destroy]

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

  private

  def invalidate_cycle_caches
    return unless audition_cycle_id

    # NOTE: audition_cycle_counts uses key versioning with audition_requests.maximum(:updated_at)
    # so it auto-invalidates when this request's updated_at changes
    # Just invalidate production dashboard
    Rails.cache.delete("production_dashboard_#{audition_cycle.production_id}") if audition_cycle&.production_id
  end
end
