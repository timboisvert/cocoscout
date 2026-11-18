# frozen_string_literal: true

# "Hours approved": the notice the Pay group's description promised (plan:
# staffing notifications §2, Tim 2026-11-07, "do it all"). Sent when a
# manager signs off hours (Timesheets → Approve, or re-approving a corrected
# entry): one notice per person, listing each entry with its hours and, where
# the member has a rate for the role, what it comes to. What happens next is
# said as it is: the money goes out on the organization's next payout run
# (named when the run is scheduled), they'll hear when it's on its way, and
# nothing reaches them until they've added a bank. Hours marked as paid
# outside CocoScout are not "approved" news and get nothing.
#
# A notification only (Tim, 2026-11-09: it emailed as well, and the
# notification opened My Payments, which says none of this). No email goes;
# a tap opens the notice's own page, with the list.
class StaffHoursApprovedNotice
  def self.send!(entries, organization:)
    new(organization).send!(entries)
  end

  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  def send!(entries)
    entries = Array(entries).select { |e| e.person&.user && e.offline_paid_at.nil? }
    return 0 if entries.empty?

    members = OrganizationStaffMember.where(organization: organization, person_id: entries.map(&:person_id).uniq)
                                     .includes(staff_role_qualifications: :house_role).index_by(&:person_id)
    entries.group_by(&:person).each do |person, list|
      bank = person.respond_to?(:can_receive_payouts?) && person.can_receive_payouts?
      deliver(person, list.sort_by(&:started_at), members[person.id], bank)
    end
    entries.map(&:person_id).uniq.size
  end

  private

  def deliver(person, list, member, bank_connected)
    cents = member ? list.sum { |e| amount_for(member, e) } : 0
    ContentTemplateService.deliver(
      template_key: "staff_hours_approved",
      variables: {
        recipient_name: ShiftWords.first_name(person),
        organization_name: organization.name,
        hours_words: hours_words(list.sum { |e| e.hours.to_d }),
        amount: (money(cents) if cents.positive?),
        entries_list: list.map { |e| list_item(e, member) }.join,
        next_line: next_line(bank_connected),
        my_payments_link: Rails.application.routes.url_helpers.my_payments_url(**ShiftWords.url_options)
      }.compact,
      sender: nil,
      recipients: [ person ],
      organization: organization,
      message_type: :system,
      visibility: :personal
    )
  end

  # "Fri, Nov 6 · Booth Tech · 5.5 hours · $49.00"
  def list_item(entry, member)
    e = ->(s) { ERB::Util.html_escape(s) }
    role = entry.effective_house_role&.name || "Additional time"
    cents = member ? amount_for(member, entry) : 0
    parts = [ "<strong>#{e.call(entry.started_at.strftime('%a, %b %-d'))}</strong>", e.call(role), e.call(hours_words(entry.hours)) ]
    parts << e.call(money(cents)) if cents.positive?
    "<li style=\"margin-bottom:6px;\">#{parts.join(' · ')}</li>"
  end

  def next_line(bank_connected)
    run =
      if organization.payout_schedule_enabled? && (on = organization.next_payout_date)
        "It goes out with the payout run on #{on.strftime('%A, %b %-d')}"
      else
        "It goes out with #{organization.name}'s next payout run"
      end
    tail = bank_connected ? "you'll hear when it's on its way." : "add your bank on My Payments so it can reach you."
    "#{run}; #{tail}"
  end

  def amount_for(member, entry)
    member.amount_cents_for(entry.effective_house_role, hours: entry.hours).to_i
  end

  def hours_words(hours)
    n = ActiveSupport::NumberHelper.number_to_rounded(hours, precision: 2, strip_insignificant_zeros: true)
    "#{n} #{hours.to_d == 1 ? 'hour' : 'hours'}"
  end

  def money(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)
  end
end
