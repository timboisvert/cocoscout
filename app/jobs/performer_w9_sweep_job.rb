# frozen_string_literal: true

# Once a day (Tim, 2026-11-22): everyone an organization has paid personally
# this year who isn't on its staff, has reached PerformerW9Requester::
# REQUEST_AT_CENTS, and has no W-9 there is requested for one; anyone already
# requested whose W-9 still isn't in is reminded once a week. Staff have their
# own request and reminders (StaffW9Requester, W9RemindersJob).
class PerformerW9SweepJob < ApplicationJob
  queue_as :background

  REMIND_EVERY = 7.days

  def perform(now: Time.current)
    year = now.year
    year_range = now.beginning_of_year..now
    # Everyone paid personally this year: through a payout run (ledger), or a
    # contract payment paid by hand, which leaves no ledger entry.
    org_ids = PayoutLedgerEntry.where(entry_type: "payout", payee_type: "Person", occurred_at: year_range).distinct.pluck(:organization_id) |
              Contract.joins(:contract_payments)
                      .where(contract_payments: { direction: "outgoing", status: "paid", payment_method: ContractPayment::OFFLINE_PAYOUT_METHODS,
                                                  paid_date: year_range.begin.to_date..year_range.end.to_date })
                      .distinct.pluck(:organization_id)
    Organization.where(id: org_ids).find_each do |organization|
      sweep(organization, year, now)
    rescue StandardError => e
      Rails.logger.error("[PerformerW9SweepJob] organization #{organization.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def sweep(organization, year, now)
    earnings = Tax::YearEarnings.for(organization, year)
    due = earnings.select { |_, result| result.net_cents >= PerformerW9Requester::REQUEST_AT_CENTS }
    return if due.empty?

    staff_ids = organization.organization_staff_members.active.where(person_id: due.keys).pluck(:person_id).to_set
    with_w9 = organization.w9_submissions.current.where(person_id: due.keys).pluck(:person_id).to_set
    requests = W9Request.where(organization: organization, person_id: due.keys).index_by(&:person_id)

    Person.where(id: due.keys - staff_ids.to_a - with_w9.to_a).includes(:user).find_each do |person|
      next unless PerformerW9Requester.requestable?(person)

      request = requests[person.id]
      next if request && request.last_sent_at > now - REMIND_EVERY

      PerformerW9Requester.call(organization: organization, person: person, paid_cents: due[person.id].net_cents,
                                tax_year: year, reminder: request.present?, now: now)
    end
  end
end
