# frozen_string_literal: true

class CourseRegistration < ApplicationRecord
  # Canonical CocoScout platform fee on course transactions. Single source of
  # truth referenced by the Stripe webhook and CoursePayoutCalculator. Applies
  # to new transactions only — existing rows store their fee in cocoscout_fee_cents.
  PLATFORM_FEE_PERCENTAGE = 10.0
  # A pending registration is the student's hold on a spot while they pay.
  HOLD = 10.minutes

  belongs_to :course_offering
  belongs_to :person
  belongs_to :user, optional: true

  has_one :production, through: :course_offering

  # Keep the org's virtual cash ledger in step with this registration — the
  # credit posts on confirmation and restates itself whenever the amounts
  # change (e.g. the hourly Stripe-fee backfill), the refund debit on refund.
  after_save :sync_org_cash_entries
  # A registration changing state changes what the course took in and therefore
  # what anyone is owed from it — a refund, a cancellation, a confirmation all
  # bring the payout back in line here, whichever path they arrived by (the
  # manage page, the Stripe webhook, the console).
  after_save :resync_course_payout, if: :money_changed?

  enum :status, {
    pending: "pending",
    confirmed: "confirmed",
    cancelled: "cancelled",
    refunded: "refunded",
    expired: "expired"
  }, default: :pending

  before_validation :assign_token, on: :create
  # What the student was told about every session, from the moment they're
  # in (CourseSessionChange reads it to know when a session moved).
  before_save :remember_sessions, if: -> { confirmed? && (status_changed? || told_sessions.blank?) && told_sessions.blank? }

  # Tax collected on it (CourseTax), reversed on a refund.
  has_many :tax_lines, as: :taxable, dependent: :delete_all

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :registered_at, presence: true

  scope :active, -> { where(status: %w[confirmed pending]) }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :pending, -> { where(status: "pending") }
  # Live holds, and holds that ran out (ExpireTicketHoldsJob marks them expired).
  scope :holding, ->(at = Time.current) { where(status: "pending").where("course_registrations.expires_at > ?", at) }
  scope :stale, ->(at = Time.current) { where(status: "pending").where("course_registrations.expires_at <= ?", at) }

  def hold_expired?
    pending? && expires_at.present? && expires_at <= Time.current
  end

  # What the student pays: the course and its tax.
  def total_cents
    amount_cents.to_i + tax_cents.to_i
  end

  # Stripe's actual fee on the charge, from its balance transaction. Best
  # effort: an hourly backfill (BackfillStripeFeeJob) fills any gap.
  def record_stripe_fee!
    charge_id = stripe_charge_id
    if charge_id.blank? && stripe_payment_intent_id.present?
      charge_id = Stripe::PaymentIntent.retrieve(stripe_payment_intent_id).latest_charge
    end
    return if charge_id.blank?

    charge = Stripe::Charge.retrieve(charge_id)
    return if charge.balance_transaction.blank?

    update!(stripe_charge_id: charge_id, stripe_fee_cents: Stripe::BalanceTransaction.retrieve(charge.balance_transaction).fee)
  rescue Stripe::StripeError => e
    Rails.logger.error "Failed to fetch Stripe fee for registration #{id}: #{e.message}"
  end

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
  # Tax collected is the org's to remit, so it rides along in full.
  def org_net_cents
    coverage = course_offering.feature_credit_redemption&.feature_credit&.coverage_type
    net = case coverage
    when "full" then amount_cents
    when "platform_only" then amount_cents - stripe_fee_cents.to_i
    else amount_cents - cocoscout_fee_cents.to_i
    end
    net + tax_cents.to_i
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
    CourseTax.reverse!(self)
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

  def assign_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end

  def remember_sessions
    self.told_sessions = CourseSessionChange.snapshot(course_offering)
  end

  # A hold starting or lapsing moves no money; a confirmation, refund or
  # cancellation does.
  def money_changed?
    return true if saved_change_to_amount_cents? && !pending? && !expired?

    saved_change_to_status? && (%w[confirmed refunded cancelled] & saved_change_to_status.compact).any?
  end

  def resync_course_payout
    CoursePayoutCalculator.new(course_offering).resync!
  end

  def cleanup_questionnaire_invitation
    return unless course_offering.questionnaire_id?

    QuestionnaireInvitation.where(
      questionnaire_id: course_offering.questionnaire_id,
      invitee: person,
      context: course_offering
    ).destroy_all
  end
end
