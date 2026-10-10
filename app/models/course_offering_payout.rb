# frozen_string_literal: true

class CourseOfferingPayout < ApplicationRecord
  STATUSES = %w[pending calculated paid].freeze
  PAYOUT_MODES = %w[lump_sum per_session].freeze
  PAYMENT_METHODS = %w[cash check bank_transfer other].freeze

  belongs_to :course_offering

  has_many :line_items, class_name: "CourseOfferingPayoutLineItem", dependent: :destroy
  has_one :production, through: :course_offering
  has_one :contract, through: :course_offering

  validates :course_offering_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :payout_mode, inclusion: { in: PAYOUT_MODES }

  scope :pending, -> { where(status: "pending") }
  scope :calculated, -> { where(status: "calculated") }
  scope :paid, -> { where(status: "paid") }

  def pending?
    status == "pending"
  end

  def calculated?
    status == "calculated"
  end

  def paid?
    status == "paid"
  end

  def can_recalculate?
    !pending?
  end

  # Effective revenue: override if set, otherwise from registrations
  def effective_revenue_cents
    total_revenue_override_cents.presence || total_revenue_cents || 0
  end

  def mark_paid!
    update!(status: "paid", paid_at: Time.current)
  end

  # A course run under a contract settles the contract's share here, in the
  # course payout, never from show financials (a course session has none).
  # Once the contractor's line is paid, by hand or on a payout run, the
  # contract's pending settlement for the run's sessions is paid with it, so
  # it never sits "TBD, overdue, awaiting ticket sales" (Tim, 2026-10-10:
  # contract 113 still said so after the $75.60 course payout went out).
  # Several settlements (one per session) are all settled; the last carries
  # the amount. Idempotent: only pending ones are touched.
  def settle_contract_payments!(line_item)
    contract = course_offering&.contract
    return unless contract && line_item.paid? && contractor_line?(line_item, contract)

    payments = contract_settlements(contract)
    return if payments.empty?

    carrier = payments.max_by { |p| [ p.due_date, p.id ] }
    paid_on = (line_item.paid_at || Time.current).to_date
    whole = ActiveSupport::NumberHelper.number_to_currency(line_item.amount_cents / 100.0)
    payments.each do |payment|
      payment.mark_paid!(paid_on: paid_on, method: "course_payout", reference: "course_offering_payout_#{id}",
                         amount: payment == carrier ? line_item.amount_cents / 100.0 : 0)
      note = payment == carrier ? "Auto-synced from course payout: #{whole} for #{course_offering.production&.name || 'the course'}." :
                                  "Auto-synced from course payout: settled in the #{whole} course payout."
      payment.update_columns(notes: [ payment.notes.presence, note ].compact.join("\n"))
    end
  end

  # Settle the payout once every line is actually paid. A payout with no
  # instructor lines is settled by its org row alone.
  def settle_if_fully_paid!
    return if paid?

    update_columns(status: "paid", paid_at: Time.current) if line_items.reload.all?(&:paid?)
  end

  # This payout is the SOURCE of the org's own remainder row on the payout run
  # (see CoursePayoutSettlement#org_row). Called when that run pays the org
  # (PayoutBatchService.settle_item_sources!): record the OrgPayout — the books'
  # record that CocoScout remitted the org its course share — and settle.
  def mark_paid_via_payout_run!(reference_id: nil)
    org_share = CoursePayoutSettlement.new(self).org_keeps_cents
    if org_share.positive?
      OrgPayout.create!(
        organization: course_offering.production.organization,
        course_offering: course_offering,
        amount_cents: org_share,
        status: "paid",
        payout_type: "full_course",
        payment_method: "bank_transfer",
        paid_at: Time.current
      )
    end
    settle_if_fully_paid!
  end

  # The run that paid the org's remainder came back — undo only what the run
  # itself recorded.
  def mark_unpaid_via_payout_run!
    update_columns(status: "calculated", paid_at: nil) if paid?
  end

  def formatted_total_revenue
    format_cents(effective_revenue_cents)
  end

  def formatted_platform_fee
    format_cents(platform_fee_cents)
  end

  def formatted_net_revenue
    format_cents(net_revenue_cents)
  end

  def formatted_total_payout
    format_cents(total_payout_cents)
  end

  private

  def contractor_line?(line_item, contract)
    contractor = contract.contractor
    return false unless contractor

    (line_item.payee_type == "Person" && contractor.person_id.present? && line_item.payee_id == contractor.person_id) ||
      (line_item.payee_type == "Contractor" && line_item.payee_id == contractor.id)
  end

  # The contract's money for this run still waiting to be paid to them:
  # settlements tied to its sessions (by show, or due the day of one), or,
  # when the contract has no other course, every settlement still waiting.
  def contract_settlements(contract)
    waiting = contract.contract_payments.direction_outgoing.status_pending.reject(&:in_payout_run?)
    sessions = course_offering.offering_shows.to_a
    ids = sessions.map(&:id)
    days = sessions.filter_map { |s| s.date_and_time&.to_date }
    covering = waiting.select { |p| ids.include?(p.show_id) || (p.show_id.nil? && days.include?(p.due_date)) }
    return covering if covering.any? || contract.course_offerings.where.not(id: course_offering_id).exists?

    settlement_ids = contract.settlement_payments.pluck(:id)
    waiting.select { |p| settlement_ids.include?(p.id) }
  end

  def format_cents(cents)
    return "$0" if cents.nil? || cents.zero?
    dollars = cents / 100.0
    if dollars == dollars.to_i
      "$#{dollars.to_i}"
    else
      "$#{'%.2f' % dollars}"
    end
  end
end
