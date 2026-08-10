# frozen_string_literal: true

# Tells each payee their money is on its way. One standard notification
# whether it's a performer, staff, or course payment — the amount is whatever
# we're actually sending them.
#
# Timing: we notify once the money has actually moved, not when the run is
# submitted. An ACH-funded run is submitted days before the debit settles, so
# announcing at submission risks promising a deposit that never lands (a
# bounced debit is never retracted) and quotes a window counted from a day
# that's already gone. We still stop short of claiming they've been *paid* —
# a transfer reaches the payee's payout-provider balance, and their bank
# deposit follows a couple of business days later.
#
# Enqueued from PayoutBatchService.process! (staff/performer/balance runs,
# which only reaches that point once funding succeeded) and from
# CoursePayoutRunExecutor.pay! (course runs, which skip funding entirely).
class PayoutSentPayeeNotificationJob < ApplicationJob
  queue_as :default

  def perform(payout_batch_id)
    batch = PayoutBatch.find_by(id: payout_batch_id)
    return unless batch
    # A run whose funding failed never promises anyone money.
    return unless batch.in_flight? || batch.completed?

    batch.items.includes(:payee).find_each do |item|
      next unless needs_notice?(item)

      person = payee_person(item)
      next unless person

      notify!(batch, item, person)
      item.update_columns(payee_notified_at: Time.current)
    rescue StandardError => e
      # One bad address must never take down the rest of a payout run.
      Rails.logger.error("[PayoutSentPayeeNotificationJob] item #{item.id}: #{e.class} #{e.message}")
    end
  end

  private

  # Notify once — except that a payee first told "your money is set aside,
  # connect a bank" deserves the real "it's on its way" once they connect and
  # a manager hits Pay remaining. That's the only case where the story we told
  # them stops being true, so it's the only case we re-send.
  #
  # A failed transfer never moved any money, and a returned one has its own
  # notification — neither may claim money is on its way. (In Aug 2026 a run
  # whose transfers all failed still emailed every payee a deposit window.)
  # A failed item that later succeeds via Pay remaining re-enters here as
  # "paid" and gets the notice then.
  def needs_notice?(item)
    return false unless %w[pending paid].include?(item.status)
    return true if item.payee_notified_at.blank?

    item.status == "paid" && item.paid_at.present? && item.paid_at > item.payee_notified_at
  end

  # The Person who actually receives the money. Organization payees are the
  # course-remainder row — the org paying itself, nobody to tell. A Contractor
  # is a container; its linked Person holds the account and the ledger.
  def payee_person(item)
    case item.payee
    when Person then item.payee
    when Contractor then item.payee.person
    end
  end

  def notify!(batch, item, person)
    has_bank = person.can_receive_payouts?
    first_payout = has_bank && first_payout_for?(person, item)
    # Count the window from the day the money actually moved. On ACH the run's
    # payday is the submit date, which can be several days stale by now.
    earliest, latest = batch.expected_deposit_range(
      first_payout: first_payout,
      from: item.paid_at&.to_date || Date.current
    )

    # One template per situation rather than one template full of conditional
    # blocks: each reads as ordinary copy in the editor, previews correctly,
    # and can't silently render to nothing if a flag goes missing.
    template_key =
      if !has_bank then "payout_sent_to_payee_no_bank"
      elsif first_payout then "payout_sent_to_payee_first_payment"
      else "payout_sent_to_payee"
      end

    url_options = mailer_url_options
    variables = {
      recipient_name: person.name.to_s.split.first.presence || person.name,
      organization_name: batch.organization.name,
      amount: ActiveSupport::NumberHelper.number_to_currency(item.amount_cents / 100.0),
      expected_window: "#{earliest.strftime('%B %-d')} – #{latest.strftime('%B %-d, %Y')}",
      payments_url: Rails.application.routes.url_helpers.my_payments_url(**url_options)
    }
    if template_key == "payout_sent_to_payee_no_bank"
      variables[:setup_url] = Rails.application.routes.url_helpers.my_payments_setup_url(**url_options)
    end

    rendered = ContentTemplateService.render(template_key, variables)

    # Email is the backbone: person.email is always present, while plenty of
    # performers have no login at all.
    PayoutBatchMailer.sent_to_payee(person: person, batch: batch, rendered: rendered).deliver_now

    # In-app copy for anyone with an account. Silently no-ops without a user.
    MessageService.send_direct(
      sender: nil,
      recipient_person: person,
      subject: rendered[:subject],
      body: rendered[:body],
      organization: batch.organization,
      system_generated: true,
      skip_digest: true
    )
  end

  # A job has no request context, so absolute URLs need the host handed to them.
  def mailer_url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end

  # True when nothing has ever been transferred to this payee before — the case
  # our payout provider holds longer while it finishes setting up the account.
  # Scoped across every organization, since the hold is per payee account, not
  # per org. Excludes the current item because course runs transfer before this
  # job runs. Offline "paid another way" records don't count: no transfer ever
  # reached the account.
  def first_payout_for?(person, item)
    !PayoutBatchItem.where(payee: person, status: "paid")
                    .where.not(id: item.id)
                    .exists?
  end
end
