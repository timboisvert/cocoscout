# frozen_string_literal: true

class AuditionCycle < ApplicationRecord
  has_many :audition_requests, dependent: :destroy
  has_many :audition_sessions, dependent: :destroy
  has_many :questions, as: :questionable, dependent: :destroy
  has_many :email_groups, dependent: :destroy
  has_many :audition_email_assignments, dependent: :destroy
  has_many :audition_reviewers, dependent: :destroy
  has_many :reviewer_people, through: :audition_reviewers, source: :person
  # NOTE: cast_assignment_stages are deleted via Production before_destroy callback
  # to avoid foreign key constraint issues with casts
  has_many :cast_assignment_stages

  has_rich_text :instruction_text
  has_rich_text :video_field_text
  has_rich_text :success_text

  belongs_to :production

  validates :opens_at, presence: true
  validate :form_must_be_reviewed_before_opening
  validate :closes_at_after_opens_at
  validate :only_one_active_per_production

  # Cache invalidation
  after_commit :invalidate_caches

  enum :audition_type, {
    in_person: "in_person",
    video_upload: "video_upload"
  }

  serialize :availability_show_ids, type: Array, coder: YAML

  def production_name
    production.name
  end

  def counts
    Rails.cache.fetch([ "audition_cycle_counts_v2", id, audition_requests.maximum(:updated_at)&.to_i ],
                      expires_in: 2.minutes) do
      {
        pending: audition_requests.where(status: :pending).count,
        approved: audition_requests.where(status: :approved).count,
        rejected: audition_requests.where(status: :rejected).count
      }
    end
  end

  def vote_summary
    Rails.cache.fetch([ "audition_cycle_vote_summary_v2", id, AuditionRequestVote.where(audition_request_id: audition_requests.select(:id)).maximum(:updated_at)&.to_i ],
                      expires_in: 2.minutes) do
      total_requests = audition_requests.count
      votes = AuditionRequestVote.where(audition_request_id: audition_requests.select(:id))

      {
        total_requests: total_requests,
        total_votes: votes.count,
        total_comments: votes.where.not(comment: [ nil, "" ]).count
      }
    end
  end

  def timeline_status
    if opens_at > Time.current
      :upcoming
    elsif closes_at.present? && closes_at <= Time.current
      :closed
    else
      :open
    end
  end

  def editable_by_talent?
    # Can only edit if:
    # - The cycle is active (not archived)
    # - The form has been reviewed/validated
    # - Current time is after opens_at and before closes_at (if closes_at is set)
    active && form_reviewed && timeline_status == :open
  end

  def respond_url
    if Rails.env.development?
      "http://localhost:3000/a/#{token}"
    else
      "https://www.cocoscout.com/a/#{token}"
    end
  end

  def form_must_be_reviewed_before_opening
    # If the audition has already started and form isn't reviewed, it should be hidden/inactive
    # (same as if it wasn't opened yet). This doesn't prevent saving the checkbox value though.
    # That's a display/UX concern, not a validation concern.
  end

  def closes_at_after_opens_at
    return unless opens_at.present? && closes_at.present? && closes_at <= opens_at

    errors.add(:closes_at, "must be after the opening date and time")
  end

  def only_one_active_per_production
    return unless active && production_id.present?

    existing = AuditionCycle.where(production_id: production_id, active: true)
                            .where.not(id: id)
                            .exists?
    return unless existing

    errors.add(:active, "can only have one active audition cycle per production")
  end

  def opening_soon?
    opens_at.present? && opens_at <= 7.days.from_now && opens_at > Time.current
  end

  def opening_soon_and_not_reviewed?
    opening_soon? && !form_reviewed
  end

  private

  def invalidate_caches
    # NOTE: counts cache uses key versioning with audition_requests.maximum(:updated_at)
    # so it auto-invalidates when requests change. We just need to clear production dashboard.
    Rails.cache.delete("production_dashboard_#{production_id}") if production_id
  end
end
