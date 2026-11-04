# frozen_string_literal: true

# Who an organization is charged for in a month.
#
# From November 2026 (Tim, 2026-11-01): everyone the organization pays
# through CocoScout in the month, by the month the money reaches their bank,
# which is how Stripe charges CocoScout for paying them ($2 an account a
# month, plus its payout fees). Staff ($5) if any of what they were paid that
# month was staff pay; everyone else ($3): performers, contractors, guests,
# instructors. Once per person per month, per organization. Paid another way
# (not through Stripe) doesn't count. November, the first month, leaves out
# anyone already billed for October under the old rule, so October's work
# paid in November isn't billed twice.
#
# Through October 2026 (Tim, 2026-10-05): a person was billable for each
# month in which they did work, once that work had happened, in a job that
# paid them money; charged to the month of the work.
#
#   Staff ($5)      — a shift in that month, already over, not declined, in a
#                     role that pays them (their rate for the role, hourly or
#                     flat, is above zero). Unpaid roles never count, and
#                     neither does a shift still ahead.
#   Performers ($3) — a show in that month, already over and not canceled,
#                     that pays them (a payout line above zero for them).
module UsageRules
  module_function

  BY_PAYMENT_FROM = Date.new(2026, 11, 1)

  def by_payment?(month)
    month.to_date.beginning_of_month >= BY_PAYMENT_FROM
  end

  def range_for(month)
    month = month.to_date.beginning_of_month
    month.in_time_zone.beginning_of_day..month.end_of_month.in_time_zone.end_of_day
  end

  # { organization_id => { person_id => time the work ended } } for staff.
  def staff(month, now: Time.current, organization: nil)
    return paid(month, organization: organization, staff: true) if by_payment?(month)

    scope = ShiftAssignment.joins(:shift).where(declined_at: nil, shifts: { starts_at: range_for(month) }).where("shifts.ends_at <= ?", now)
    scope = scope.where(shifts: { organization_id: organization.id }) if organization
    rows = scope.pluck("shifts.organization_id", :person_id, "shifts.house_role_id", "shifts.ends_at")
    return {} if rows.empty?

    roles = HouseRole.where(id: rows.map { |r| r[2] }.uniq).index_by(&:id)
    members = OrganizationStaffMember.where(person_id: rows.map { |r| r[1] }.uniq, organization_id: rows.map(&:first).uniq)
                                     .includes(:staff_role_qualifications).index_by { |m| [ m.organization_id, m.person_id ] }
    rows.each_with_object(Hash.new { |h, k| h[k] = {} }) do |(org_id, person_id, role_id, ended_at), out|
      member = members[[ org_id, person_id ]]
      role = roles[role_id]
      next unless member && role && paid_role?(member, role)

      out[org_id][person_id] = [ out[org_id][person_id], ended_at ].compact.min
    end
  end

  # { organization_id => { person_id => show time } } for performers.
  def performers(month, now: Time.current, organization: nil)
    return paid(month, organization: organization, staff: false) if by_payment?(month)

    scope = ShowPayoutLineItem.joins(show_payout: { show: :production })
                              .where(payee_type: "Person", is_guest: false, shows: { canceled: false, date_and_time: range_for(month) })
                              .where("shows.date_and_time <= ?", now).where("show_payout_line_items.amount > 0")
    scope = scope.where(productions: { organization_id: organization.id }) if organization
    scope.pluck("productions.organization_id", :payee_id, "shows.date_and_time")
         .each_with_object(Hash.new { |h, k| h[k] = {} }) do |(org_id, person_id, at), out|
      out[org_id][person_id] = [ out[org_id][person_id], at ].compact.min
    end
  end

  # When a payment reached the payee's bank: the deposit Stripe reported,
  # else the day it was due, else the day we sent it.
  def deposited_at(item)
    item.deposited_at || item.expected_deposit_on&.in_time_zone&.change(hour: 12) || item.paid_at
  end

  # Everyone paid through Stripe in the month, by organization: the staff
  # (any staff pay among what reached them that month), or everyone else.
  # { organization_id => { person_id => when it reached their bank } }
  def paid(month, organization: nil, staff:)
    month = month.to_date.beginning_of_month
    range = range_for(month)
    # Sent up to a week before the month: a payment sent on the 30th can
    # reach the bank on the 2nd.
    items = PayoutBatchItem.paid.where(payee_type: "Person").where.not(stripe_transfer_id: nil)
                           .where(paid_at: (range.first - 7.days)..range.last).includes(:payout_batch)
    items = items.joins(:payout_batch).where(payout_batches: { organization_id: organization.id }) if organization
    items = items.to_a.select { |item| range.cover?(deposited_at(item)) }
    return {} if items.empty?

    staffed = PayoutContribution.payable.where(payout_batch_item_id: items.map(&:id), category: "staffing")
                                .where("amount_cents > 0").distinct.pluck(:payout_batch_item_id).to_set
    out = Hash.new { |h, k| h[k] = {} }
    staff_people = Hash.new { |h, k| h[k] = Set.new }
    items.each { |item| staff_people[item.payout_batch.organization_id] << item.payee_id if staffed.include?(item.id) }
    items.each do |item|
      org_id = item.payout_batch.organization_id
      next unless staff_people[org_id].include?(item.payee_id) == staff

      out[org_id][item.payee_id] = [ out[org_id][item.payee_id], deposited_at(item) ].compact.min
    end
    leave_out_billed_in_october!(out) if month == BY_PAYMENT_FROM
    out
  end

  # The first month by payment: October's bill already counted October's
  # work, so whoever it billed isn't billed again for being paid in November.
  def leave_out_billed_in_october!(out)
    october = BY_PAYMENT_FROM.prev_month
    out.each do |org_id, people|
      billed = PerformerActivation.where(organization_id: org_id).for_month(october).pluck(:person_id) +
               StaffActivation.where(organization_id: org_id).for_month(october).pluck(:person_id)
      people.except!(*billed)
    end
    out.reject! { |_, people| people.empty? }
  end

  # Bank debits beyond the free ones in a month cost a flat fee each, on the
  # month's usage bill (Tim, 2026-11-01: two free a month, then $5, to
  # encourage bigger, fewer debits). A bank debit is a payout run funded
  # from the organization's bank, or funds it added from its bank.
  FREE_BANK_DEBITS = 2
  EXTRA_BANK_DEBIT_CENTS = 500

  # The month's bank debits, oldest first: [when, what, cents]. An
  # organization that funds with a card has none.
  def bank_debits(organization, month)
    return [] if organization.funding_payment_method_type == "card"

    range = range_for(month)
    runs = PayoutBatch.where(organization: organization).where.not(funding_payment_intent_id: nil)
                      .where("COALESCE(funding_started_at, created_at) BETWEEN ? AND ?", range.first, range.last)
                      .pluck(Arel.sql("COALESCE(funding_started_at, created_at)"), :total_cents)
                      .map { |at, cents| [ at, "Payout run funded from your bank", cents ] }
    top_ups = BalanceTopUp.where(organization: organization, created_at: range).where.not(stripe_payment_intent_id: nil)
                          .pluck(:created_at, :amount_cents).map { |at, cents| [ at, "Funds added from your bank", cents ] }
    (runs + top_ups).sort_by(&:first)
  end

  def extra_bank_debits(organization, month)
    return 0 unless by_payment?(month)

    [ bank_debits(organization, month).size - FREE_BANK_DEBITS, 0 ].max
  end

  def bank_debit_fee_cents(organization, month)
    extra_bank_debits(organization, month) * EXTRA_BANK_DEBIT_CENTS
  end

  # Withdrawals to the organization's own bank are free up to $5,000 a month;
  # above that it pays our payment provider's 0.25% on the part over, on the
  # month's usage bill (Tim, 2026-11-01: passing on our cost, not making
  # money on it).
  FREE_WITHDRAWAL_CENTS = 500_000
  WITHDRAWAL_FEE_BASIS_POINTS = 25

  def withdrawn_cents(organization, month)
    BalanceWithdrawal.not_failed.where(organization: organization, created_at: range_for(month)).sum(:amount_cents)
  end

  def withdrawal_fee_cents(organization, month, withdrawn = nil)
    return 0 unless by_payment?(month)

    over = [ (withdrawn || withdrawn_cents(organization, month)) - FREE_WITHDRAWAL_CENTS, 0 ].max
    (over * WITHDRAWAL_FEE_BASIS_POINTS / 10_000.0).round
  end

  # Everything the month's usage bill charges beyond the people paid: Pro
  # when it's paid on this bill, and the fees.
  def fees_cents(organization, month)
    pro_cents(organization, month) + bank_debit_fee_cents(organization, month) + withdrawal_fee_cents(organization, month)
  end

  # Pro for the month, when the organization pays it on the monthly bill
  # (Organization#pro_on_monthly_bill?): $29, by the day for a month it
  # started or ended part way through, and nothing for days it was comped.
  def pro_cents(organization, month)
    return 0 if organization.pro_monthly_from.blank?

    range = range_for(month)
    from = [ organization.pro_monthly_from, range.first ].max
    to = [ organization.pro_monthly_until || range.last, range.last ].min
    comp_end = organization.comped_indefinitely? ? range.last : organization.comped_until
    from = [ from, comp_end + 1.second ].max if comp_end
    return 0 if to <= from

    # Whole days, the first day counted: ending at midnight leaves that day out.
    last_day = to == to.beginning_of_day ? to.to_date - 1 : to.to_date
    days = (last_day - from.to_date).to_i + 1
    month_days = month.to_date.end_of_month.day
    days >= month_days ? SubscriptionPlan::PRO_MONTHLY_CENTS : (SubscriptionPlan::PRO_MONTHLY_CENTS * days / month_days.to_f).round
  end

  def paid_role?(member, role)
    cents = role.flat? ? member.flat_cents_for(role) : member.rate_cents_for(role)
    cents.to_i.positive?
  end
end
