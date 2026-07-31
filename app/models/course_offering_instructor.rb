# frozen_string_literal: true

class CourseOfferingInstructor < ApplicationRecord
  belongs_to :course_offering
  belongs_to :person

  has_one_attached :headshot

  has_rich_text :bio

  validates :person_id, uniqueness: { scope: :course_offering_id }

  # Standalone (no-contract) payout split for this instructor on this run.
  PAYOUT_TYPES = %w[none percentage flat].freeze
  validates :payout_type, inclusion: { in: PAYOUT_TYPES }
  validates :payout_percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :payout_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  default_scope { order(:position) }

  # The cents this instructor is owed for a given net-revenue amount, per their
  # configured split. Zero when unset.
  def payout_amount_cents(net_revenue_cents)
    case payout_type
    when "percentage" then (net_revenue_cents * payout_percentage.to_f / 100.0).round
    when "flat" then payout_cents.to_i
    else 0
    end
  end
end
