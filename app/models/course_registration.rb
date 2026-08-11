# frozen_string_literal: true

class CourseRegistration < ApplicationRecord
  # Canonical CocoScout platform fee on course transactions. Single source of
  # truth referenced by the Stripe webhook and CoursePayoutCalculator. Applies
  # to new transactions only — existing rows store their fee in cocoscout_fee_cents.
  PLATFORM_FEE_PERCENTAGE = 10.0

  belongs_to :course_offering
  belongs_to :person
  belongs_to :user, optional: true

  has_one :production, through: :course_offering

  # Keep the org's virtual cash ledger in step with this registration — the
  # credit posts on confirmation and restates itself whenever the amounts
  # change (e.g. the hourly Stripe-fee backfill), the refund debit on refund.
  after_save :sync_org_cash_entries

  enum :status, {
    pending: "pending",
    confirmed: "confirmed",
    cancelled: "cancelled",
    refunded: "refunded"
  }, default: :pending

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :registered_at, presence: true

  scope :active, -> { where(status: %w[confirmed pending]) }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :pending, -> { where(status: "pending") }

  def formatted_amount
    return "$0" if amount_cents.nil? || amount_cents.zero?
    dollars = amount_cents / 100.0
    if dollars == dollars.to_i
      "$#{dollars.to_i}"
    else
      "$#{'%.2f' % dollars}"
    end
  end

  def organization
    course_offering&.production&.organization
  end

  # The platform fee to charge on a registration, honoring the offering's promo
  # coverage. Single source of truth for the webhook and the success-page
  # fallback (which used to skip the fee entirely, over-crediting the org).
  def self.platform_fee_cents_for(offering, amount_cents)
    if offering.feature_credit_redemption.present?
      # "full" waives everything; "platform_only" waives CocoScout's cut while
      # Stripe's own fee still applies. Either way our fee is 0.
      0
    else
      (amount_cents * PLATFORM_FEE_PERCENTAGE / 100.0).round
    end
  end

  # The org's net share of this registration — what CocoScout holds for them in
  # the shared Stripe balance. Mirrors OrgPayout.owed_cents_for_course, per row.
  def org_net_cents
    coverage = course_offering.feature_credit_redemption&.feature_credit&.coverage_type
    case coverage
    when "full" then amount_cents
    when "platform_only" then amount_cents - stripe_fee_cents.to_i
    else amount_cents - cocoscout_fee_cents.to_i
    end
  end

  def cancel!
    update!(status: :cancelled, cancelled_at: Time.current)
    cleanup_questionnaire_invitation
  end

  def refund!(stripe_refund_id: nil)
    update!(
      status: :refunded,
      refunded_at: Time.current,
      stripe_refund_id: stripe_refund_id.presence || self.stripe_refund_id
    )
    cleanup_questionnaire_invitation
  end

  # Post (or restate) this registration's lines in the org cash ledger. Only
  # money that actually entered the shared Stripe balance counts, so free spots
  # and hand-recorded registrations post nothing. A refund keeps both halves on
  # the ledger: the original credit and a matching refund debit.
  # Public so the one-time backfill can replay history through the same code.
  def sync_org_cash_entries
    return unless confirmed? || refunded?
    return if stripe_payment_intent_id.blank? && stripe_checkout_session_id.blank?

    org = organization
    return unless org

    net = org_net_cents
    return unless net.positive?

    OrgCashEntry.post!(
      organization: org,
      entry_type: "course_registration",
      amount_cents: net,
      source: self,
      description: "Course registration ##{id} (#{course_offering.title})",
      occurred_at: paid_at || registered_at
    )

    if refunded?
      OrgCashEntry.post!(
        organization: org,
        entry_type: "refund",
        amount_cents: -net,
        source: self,
        description: "Refund of course registration ##{id}",
        occurred_at: refunded_at || Time.current
      )
    end
  end

  private

  def cleanup_questionnaire_invitation
    return unless course_offering.questionnaire_id?

    QuestionnaireInvitation.where(
      questionnaire_id: course_offering.questionnaire_id,
      invitee: person,
      context: course_offering
    ).destroy_all
  end
end
