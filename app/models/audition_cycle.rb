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

  # Set default for reviewer_access_type
  after_initialize :set_default_reviewer_access_type, if: :new_record?

  # Cache invalidation
  after_commit :invalidate_caches

  # Keep the enum for now (for backward compatibility during transition)
  # but also provide new boolean-based methods
  enum :audition_type, {
    in_person: "in_person",
    video_upload: "video_upload"
  }

  # New boolean-based methods that should be used going forward
  # These check the new columns, with fallback to the enum for existing records
  def accepts_video_submissions?
    allow_video_submissions
  end

  def accepts_in_person_auditions?
    allow_in_person_auditions
  end

  def video_only?
    allow_video_submissions && !allow_in_person_auditions
  end

  def in_person_only?
    allow_in_person_auditions && !allow_video_submissions
  end

  def hybrid_auditions?
    allow_video_submissions && allow_in_person_auditions
  end

  # Validation: at least one format must be enabled
  validate :at_least_one_audition_format

  serialize :availability_show_ids, type: Array, coder: YAML

  def production_name
    production.name
  end

  def counts
    Rails.cache.fetch([ "audition_cycle_counts_v3", id, audition_requests.maximum(:updated_at)&.to_i ],
                      expires_in: 2.minutes) do
      # Count scheduled vs not scheduled for in-person, or cast vs not cast for video upload
      scheduled_count = audition_sessions.joins(:auditions).distinct.count("auditions.auditionable_id")
      cast_count = cast_assignment_stages.count

      {
        total: audition_requests.count,
        scheduled: scheduled_count,
        cast: cast_count
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

  def reviewer_count
    access_type = reviewer_access_type.presence || "managers"
    case access_type
    when "managers"
      # Count global managers/viewers + production-level managers/viewers
      global_user_ids = production.organization.organization_roles.where(company_role: %w[manager viewer]).pluck(:user_id)
      production_user_ids = production.production_permissions.where(role: %w[manager viewer]).pluck(:user_id)
      (global_user_ids + production_user_ids).uniq.count
    when "all"
      # Count all effective talent pool members (may include shared pool)
      production.effective_talent_pool&.people&.count || 0
    when "specific"
      # Count specifically assigned reviewers
      audition_reviewers.count
    else
      0
    end
  end

  private

  def set_default_reviewer_access_type
    self.reviewer_access_type ||= "managers"
  end

  def at_least_one_audition_format
    return if allow_video_submissions || allow_in_person_auditions

    errors.add(:base, "You must enable at least one audition format (video submissions or in-person auditions)")
  end

  def invalidate_caches
    # NOTE: counts cache uses key versioning with audition_requests.maximum(:updated_at)
    # so it auto-invalidates when requests change. We just need to clear production dashboard.
    Rails.cache.delete("production_dashboard_#{production_id}") if production_id
  end
end
