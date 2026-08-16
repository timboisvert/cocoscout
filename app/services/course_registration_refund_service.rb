# frozen_string_literal: true

# Refunds one confirmed course registration: reserves the money on the org's
# cash ledger, sends the refund through Stripe, marks the registration refunded
# (which dissolves what anyone was owed from it — CourseRegistration's payout
# resync), and releases the reservation if Stripe says no.
#
# The one place a refund happens, whether a manager clicks it on the course page
# or a whole course is cancelled (CourseCancellationJob). Never call Stripe from
# here on a request thread for more than one registration — the job exists for
# that.
class CourseRegistrationRefundService
  Result = Struct.new(:ok, :error, keyword_init: true) do
    def ok? = ok
  end

  def self.call(registration)
    new(registration).call
  end

  def initialize(registration)
    @registration = registration
  end

  def call
    return Result.new(ok: false, error: "Only confirmed registrations can be refunded.") unless @registration.confirmed?

    # Nothing was ever charged — just mark it.
    if @registration.stripe_payment_intent_id.blank?
      @registration.refund!
      return Result.new(ok: true)
    end

    # The refund leaves the shared Stripe balance, so it must fit within this
    # org's own held money — reserve it on the cash ledger first.
    net = @registration.org_net_cents
    if net.positive?
      begin
        OrgCashEntry.debit!(
          organization: @registration.organization,
          amount_cents: net,
          source: @registration,
          entry_type: "refund",
          description: "Refund of course registration ##{@registration.id}"
        )
      rescue OrgCashEntry::InsufficientFunds
        return Result.new(ok: false, error: "Your organization's held balance can't cover this refund right now.")
      end
    end

    refund = Stripe::Refund.create(
      payment_intent: @registration.stripe_payment_intent_id,
      metadata: { organization_id: @registration.organization&.id, course_registration_id: @registration.id }
    )
    # The webhook will also call refund! when charge.refunded fires; marking it
    # here gives immediate feedback and captures the exact Stripe refund id.
    @registration.refund!(stripe_refund_id: refund.id)
    Result.new(ok: true)
  rescue Stripe::StripeError => e
    # The money never left — release the reservation.
    OrgCashEntry.unpost!(source: @registration, entry_type: "refund")
    Result.new(ok: false, error: "Refund failed: #{e.message}")
  end
end
