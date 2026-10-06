# frozen_string_literal: true

# Who an organization is charged for in a month (Tim, 2026-10-05): a person
# is billable for each month in which they did work, once that work has
# happened, in a job that pays them money. Charged to the month of the work,
# not the month the money went out; once per person per month.
#
#   Staff ($5)      — a shift in that month, already over, not declined, in a
#                     role that pays them (their rate for the role, hourly or
#                     flat, is above zero). Unpaid roles never count, and
#                     neither does a shift still ahead.
#   Performers ($3) — a show in that month, already over and not canceled,
#                     that pays them (a payout line above zero for them).
module UsageRules
  module_function

  def range_for(month)
    month = month.to_date.beginning_of_month
    month.in_time_zone.beginning_of_day..month.end_of_month.in_time_zone.end_of_day
  end

  # { organization_id => { person_id => time the work ended } } for staff.
  def staff(month, now: Time.current, organization: nil)
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
    scope = ShowPayoutLineItem.joins(show_payout: { show: :production })
                              .where(payee_type: "Person", is_guest: false, shows: { canceled: false, date_and_time: range_for(month) })
                              .where("shows.date_and_time <= ?", now).where("show_payout_line_items.amount > 0")
    scope = scope.where(productions: { organization_id: organization.id }) if organization
    scope.pluck("productions.organization_id", :payee_id, "shows.date_and_time")
         .each_with_object(Hash.new { |h, k| h[k] = {} }) do |(org_id, person_id, at), out|
      out[org_id][person_id] = [ out[org_id][person_id], at ].compact.min
    end
  end

  def paid_role?(member, role)
    cents = role.flat? ? member.flat_cents_for(role) : member.rate_cents_for(role)
    cents.to_i.positive?
  end
end
