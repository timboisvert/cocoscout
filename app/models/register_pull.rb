# frozen_string_literal: true

# One line of an integration's pull log: when, for which days, how many
# orders, and whether it finished.
class RegisterPull < ApplicationRecord
  TRIGGERS = %w[morning webhook manual].freeze
  STATUSES = %w[running done failed].freeze

  belongs_to :integration

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(started_at: :desc) }

  def done? = status == "done"
  def failed? = status == "failed"

  def what
    days = from_date == to_date ? from_date.strftime("%b %-d") : "#{from_date.strftime('%b %-d')} to #{to_date.strftime('%b %-d')}"
    detail = failed? ? error.to_s.truncate(80) : (orders_count.zero? ? "nothing sold" : "#{orders_count} #{'order'.pluralize(orders_count)}")
    "#{days}: #{detail}"
  end

  def trigger_label
    { "morning" => "The morning pull", "webhook" => "Orders closing during the night", "manual" => "Pull now" }.fetch(trigger)
  end
end
