# frozen_string_literal: true

class TicketingSyncLog < ApplicationRecord
  belongs_to :ticketing_provider
  belongs_to :ticketing_production_link, optional: true
  belongs_to :user, optional: true

  has_one :organization, through: :ticketing_provider

  # Sync types
  SYNC_TYPES = %w[full incremental manual webhook].freeze

  # Statuses
  STATUSES = %w[started success partial failed].freeze

  # Validations
  validates :sync_type, presence: true, inclusion: { in: SYNC_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }
  scope :for_provider, ->(provider_id) { where(ticketing_provider_id: provider_id) }

  # Start a new sync log
  def self.start!(ticketing_provider:, sync_type:, production_link: nil, user: nil)
    create!(
      ticketing_provider: ticketing_provider,
      ticketing_production_link: production_link,
      user: user,
      sync_type: sync_type,
      status: "started",
      started_at: Time.current
    )
  end

  # Mark sync as successful
  def mark_success!
    update!(
      status: "success",
      completed_at: Time.current
    )
  end

  # Mark sync as partial (some records failed)
  def mark_partial!(error_message = nil)
    update!(
      status: "partial",
      error_message: error_message&.truncate(1000),
      completed_at: Time.current
    )
  end

  # Mark sync as failed
  def mark_failed!(error, backtrace: nil)
    update!(
      status: "failed",
      error_message: error.to_s.truncate(1000),
      error_backtrace: backtrace&.first(10)&.join("\n"),
      completed_at: Time.current
    )
  end

  # Increment record counters
  def increment_processed!
    increment!(:records_processed)
  end

  def increment_created!
    increment!(:records_created)
    increment!(:records_processed)
  end

  def increment_updated!
    increment!(:records_updated)
    increment!(:records_processed)
  end

  def increment_failed!
    increment!(:records_failed)
    increment!(:records_processed)
  end

  # Duration in seconds
  def duration
    return nil unless started_at && completed_at

    completed_at - started_at
  end

  # Human-readable duration
  def duration_text
    return "In progress..." unless completed_at

    seconds = duration.to_i
    if seconds < 60
      "#{seconds}s"
    else
      "#{seconds / 60}m #{seconds % 60}s"
    end
  end

  # Check if this was a manual sync
  def manual?
    sync_type == "manual"
  end

  # Check if this was triggered by a webhook
  def webhook?
    sync_type == "webhook"
  end

  # Summary text
  def summary
    parts = []
    parts << "#{records_created} created" if records_created.positive?
    parts << "#{records_updated} updated" if records_updated.positive?
    parts << "#{records_failed} failed" if records_failed.positive?

    return "No changes" if parts.empty?

    parts.join(", ")
  end
end
