# frozen_string_literal: true

# Everything a change to some dates touches, worked out before anything
# happens (Tim, 2026-11-27, "Cancel or move this date"). The screens show
# it, the review sentences come from it, and ShowChangePlan::Apply does it.
#
#   plan = ShowChangePlan.new(date_change)
#   plan.buyers / plan.cast / plan.staff / plan.signups / plan.students
#   plan.money / plan.followers / plan.contract
#   plan.automatic   # what happens on its own, in sentences
#
# A cancel reads the dates as they stand; a move also reads where they go
# (ShowChangePlan::Moves); a restore reads what the cancel it undoes took off.
class ShowChangePlan
  PASS_CHANNELS = %w[pass door_pass].freeze
  OTHER_PATHS = %w[cash external].freeze

  Order = Data.define(:order, :kind, :cents, :tickets) do
    def email = order.buyer_email.to_s.strip.downcase.presence
    def show = order.ticket_listing.show
  end

  Buyers = Data.define(:orders, :comp_requests) do
    def of(kind) = orders.select { |o| o.kind == kind }
    def card = of(:card)
    def other = of(:other)
    def pass = of(:pass)
    def comps = of(:comp)
    def paying = orders.reject { |o| o.kind == :comp }
    def any? = orders.any? || comp_requests.any?
    def ticket_count = orders.sum(&:tickets)
    def buyer_count(list = orders) = list.map { |o| o.email || "order-#{o.order.id}" }.uniq.size
    def paid_cents = paying.sum(&:cents)
    def card_cents = card.sum(&:cents)
    def other_cents = other.sum(&:cents)
    def emailable = orders.select(&:email)
  end

  CastPerson = Data.define(:person, :roles, :dates) do
    def reachable? = person.user.present? || person.email.present?
  end
  Cast = Data.define(:people, :vacancies, :table_events) do
    def any? = people.any? || vacancies.any? || table_events.any?
    def unreachable = people.reject(&:reachable?)
    def invited_count = vacancies.sum { |v| v.invitations.size }
  end

  ShiftLine = Data.define(:shift, :person, :status, :reason) do
    # status: :changes (comes off, or moves), :stays, :open (nobody on it)
  end
  Staff = Data.define(:lines, :vacancies) do
    def changing = lines.select { |l| l.status == :changes }
    def staying = lines.select { |l| l.status == :stays }
    def open_shifts = lines.select { |l| l.status == :open }
    def people = changing.map(&:person).compact.uniq
    def changing_shifts = (changing + open_shifts).map(&:shift).uniq
    def any? = lines.any?
  end

  Signups = Data.define(:instances, :registrations) do
    def any? = registrations.any? || instances.any?
  end

  Money = Data.define(:payouts, :expenses, :contract_payments) do
    def any? = payouts.any? || expenses.any? || contract_payments.any?
  end

  attr_reader :change, :organization

  def initialize(change)
    @change = change
    @organization = change.organization
  end

  def shows = @shows ||= change.shows
  def show_ids = shows.map(&:id)
  def live_shows = shows.reject(&:canceled?)
  def upcoming_shows = live_shows.reject { |s| s.date_and_time < Time.current }
  def origin = change.show || shows.first
  def productions = shows.map(&:production).uniq

  # The dates a cancel or move acts on (not ones already canceled); a
  # restore acts on the canceled ones.
  def acting_shows = @acting_shows ||= (change.restore? ? shows.select(&:canceled?) : live_shows)
  def acting_ids = acting_shows.map(&:id)

  # ---- Ticket buyers ------------------------------------------------------

  def listings
    @listings ||= TicketListing.where(show_id: acting_ids).includes(:show).to_a
  end

  def buyers
    @buyers ||= begin
      orders = TicketOrder.where(ticket_listing_id: listings.map(&:id)).paid_like
                          .includes(:tickets, ticket_listing: :show).order(:buyer_name).to_a
      rows = orders.filter_map do |order|
        sold = order.tickets.count { |t| t.status.in?(Ticket::SOLD_STATUSES) }
        next if sold.zero?

        kind = if order.channel.in?(PASS_CHANNELS) then :pass
        elsif order.money_path == "none" then :comp
        elsif order.money_path.in?(OTHER_PATHS) then :other
        else :card
        end
        cents = kind.in?(%i[card other]) ? refund_cents(order) : 0
        Order.new(order: order, kind: kind, cents: cents, tickets: sold)
      end
      requests = CompRequest.waiting.where(ticket_listing_id: listings.map(&:id)).includes(:requested_by, ticket_listing: :show).to_a
      Buyers.new(orders: rows, comp_requests: requests)
    end
  end

  # The refunded orders of a cancel (what a restore can email).
  def refunded_orders
    TicketOrder.where(id: Array(change.restores&.undo&.dig("refunded_order_ids"))).includes(ticket_listing: :show).to_a
  end

  # ---- Cast ---------------------------------------------------------------

  def cast
    @cast ||= begin
      people = Hash.new { |h, k| h[k] = { roles: [], dates: [] } }
      acting_shows.each do |show|
        ShowChanges.cast_entries(show).each do |entry|
          people[entry["person_id"]][:roles] |= entry["roles"]
          people[entry["person_id"]][:dates] |= [ show.date_and_time ]
        end
      end
      records = Person.where(id: people.keys).includes(:user, profile_headshots: { image_attachment: :blob }).index_by(&:id)
      list = people.filter_map do |id, v|
        records[id] && CastPerson.new(person: records[id], roles: v[:roles], dates: v[:dates].sort)
      end.sort_by { |c| c.person.name.to_s.downcase }
      vacancies = change.cancel? ? cant_make_it_requests : []
      events = change.cancel? ? CastingTableEvent.where(show_id: acting_ids).includes(:casting_table).to_a : []
      Cast.new(people: list, vacancies: vacancies, table_events: events)
    end
  end

  def cant_make_it_requests
    ids = acting_ids
    RoleVacancy.active.where(show_id: ids)
               .or(RoleVacancy.active.where(id: RoleVacancyShow.where(show_id: ids).select(:role_vacancy_id)))
               .includes(:role, :show, invitations: { person: :user }).distinct.to_a
  end

  # ---- Staff --------------------------------------------------------------

  # Each shift the dates touch: the ones that come off (or move) with them,
  # the ones nobody is on yet, and the ones that stay because they're also
  # there for a date that isn't changing.
  def staff
    @staff ||= begin
      kind = change.cancel? ? "canceled" : "moved"
      off = change.cancel? ? acting_ids : []
      changing = {}
      tied = {}
      acting_shows.each do |show|
        ShowChanges.shifts_for(show, kind, off_ids: off).each { |s| changing[s.id] = s }
        tied_shifts(show).each { |s| tied[s.id] = s }
      end
      lines = []
      changing.each_value do |shift|
        people = shift.active_assignments.filter_map(&:person)
        if people.empty?
          lines << ShiftLine.new(shift: shift, person: nil, status: :open, reason: nil)
        else
          people.each { |p| lines << ShiftLine.new(shift: shift, person: p, status: :changes, reason: nil) }
        end
      end
      (tied.keys - changing.keys).each do |id|
        shift = tied[id]
        others = shift.covered_shows.reject { |s| s.canceled? || off.include?(s.id) || acting_ids.include?(s.id) }
        reason = if others.any?
          "also covers #{others.map { |s| "#{s.display_name.presence || s.production.name} at #{s.date_and_time.strftime('%-l:%M %p').strip}" }.to_sentence}, which #{others.one? ? "isn't" : "aren't"} #{change.cancel? ? 'canceled' : 'moving'}"
        else
          "is a house shift for the whole day, and other events are still on that day"
        end
        people = shift.active_assignments.filter_map(&:person)
        (people.presence || [ nil ]).each { |p| lines << ShiftLine.new(shift: shift, person: p, status: :stays, reason: reason) }
      end
      lines.sort_by! { |l| [ l.shift.starts_at, l.person&.name.to_s ] }
      vacancies = ShiftVacancy.active.where(shift_id: changing.keys).includes(:shift).to_a
      Staff.new(lines: lines, vacancies: vacancies)
    end
  end

  def tied_shifts(show)
    Shift.where(organization: organization, source_type: "Show", source_id: show.id)
         .or(Shift.where(organization: organization, id: ShiftShow.where(show_id: show.id).select(:shift_id)))
         .includes(:house_role, :additional_roles, :source, :shows, shift_assignments: :person).to_a
  end

  # ---- Sign-ups and classes -------------------------------------------------

  def signups
    @signups ||= begin
      instances = SignUpFormInstance.where(show_id: acting_ids).includes(:sign_up_form).to_a
      ids = instances.map(&:id)
      regs = SignUpRegistration.active
                               .where(sign_up_slot_id: SignUpSlot.where(sign_up_form_instance_id: ids).select(:id))
                               .or(SignUpRegistration.active.where(sign_up_form_instance_id: ids))
                               .includes(:person, sign_up_slot: :sign_up_form_instance).to_a
      Signups.new(instances: instances, registrations: regs)
    end
  end

  def signup_form_names = signups.instances.map { |i| i.sign_up_form.name }.uniq

  def students
    @students ||= change.cancel? ? CourseSessionCancellation.summary(acting_shows).registrations.to_a : []
  end

  def class_offerings = acting_shows.filter_map(&:course_offering).uniq

  # ---- Money --------------------------------------------------------------

  def money
    @money ||= begin
      payouts = ShowPayout.where(show_id: acting_ids).includes(:show).to_a.reject { |p| p.paid? || p.in_payout_run? }
      expenses = ProductionExpense.active.where(production_id: acting_shows.map(&:production_id).uniq)
                                  .where(id: ProductionExpenseAllocation.where(show_id: acting_ids, is_override: false).select(:production_expense_id))
                                  .to_a.select(&:exclude_canceled?)
      payments = ContractPayment.where(show_id: acting_ids, status: %w[pending overdue])
                                .joins(:contract).where(contracts: { organization_id: organization.id })
                                .to_a.reject(&:in_payout_run?)
      Money.new(payouts: payouts, expenses: change.cancel? ? expenses : [], contract_payments: change.cancel? ? payments : [])
    end
  end

  # How many of an expense's dates are left once these are off.
  def expense_dates_after(expense)
    expense.applicable_shows.reject { |s| acting_ids.include?(s.id) }.size
  end

  # ---- Followers ----------------------------------------------------------

  def follower_drafts
    @follower_drafts ||= begin
      ids = acting_ids
      organization.follower_emails.drafts.to_a.select { |d| (Array(d.show_ids).map(&:to_i) & ids).any? }
    end
  end

  # ---- Contracts ----------------------------------------------------------

  def rentals
    @rentals ||= SpaceRental.where(id: acting_shows.filter_map(&:space_rental_id).uniq).includes(:contract, :location_space).to_a
  end

  # A rental is let go only when every date in it is going.
  def rentals_to_release
    rentals.select { |r| Show.where(space_rental_id: r.id, canceled: false).where.not(id: acting_ids).none? }
  end

  def following_copies
    @following_copies ||= Show.where(linked_show_id: acting_ids).includes(production: :organization).to_a
  end

  # ---- What happens on its own ----------------------------------------------

  def automatic
    lines = []
    n = acting_shows.size
    dates = { 1 => "the date", 2 => "both dates" }[n] || "all #{n} dates"
    case change.kind
    when "cancel"
      lines << "Ticket sales stop on #{dates}." if listings.any?
      lines << "#{n == 1 ? 'The date reads' : 'The dates read'} Canceled on your calendar and #{n == 1 ? 'comes' : 'come'} off your public pages."
      lines << "Your Google Calendar shows #{n == 1 ? 'it' : 'them'} as canceled." if GoogleCalendarSync.on_for?(organization.id)
      lines << "Reminders for #{n == 1 ? 'this date' : 'these dates'} don't go out."
      rooms = acting_shows.filter_map { |s| s.location_space&.name || s.location&.name }.uniq
      lines << "#{rooms.to_sentence} #{rooms.one? ? 'is' : 'are'} free for other bookings then." if rooms.any?
      following_copies.map { |s| s.production.organization.name }.uniq.each do |name|
        lines << "#{name}'s own copy of #{n == 1 ? 'the date' : 'these dates'} is canceled too."
      end
    when "restore"
      lines << "Ticket sales reopen, on the same ticket types." if listings.any?
      lines << "#{n == 1 ? 'The date comes' : 'The dates come'} back on your calendar and public pages."
      lines << "Reminders go out again."
    end
    lines
  end

  private

  def refund_cents(order)
    TicketOrderRefund.quote(order, reprice: false).amount_cents
  rescue StandardError
    order.total_cents.to_i
  end
end
