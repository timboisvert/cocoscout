# frozen_string_literal: true

# Production Home's days, show by show (Tim, 2026-10-27: "It needs to be
# show by show"): for each show in the range, where its tickets, its staffing
# and its cast stand, in a handful of queries for the lot. The controller
# hands over the shows (already scoped to what the person can see) and each
# show's cast; this works out the rest.
#
#   tickets_on?   Pro managers, once the organization sells tickets
#   staffing_on?  Pro managers, once the organization has staffing roles
#
# Each row's :tickets, :staffing and :cast is nil when that part doesn't
# apply to the organization, so the page draws nothing for it.
class HomeWeek
  Row = Data.define(:show, :signups, :tickets, :staffing, :cast, :told)
  # A canceled show, or one moved with people not told yet: who's been told
  # (ShowChanges; docs/show_change_notices_plan.md). change is nil for a show
  # canceled before changes were recorded (Tell them now makes one).
  Told = Data.define(:show, :kind, :change, :cast_ids, :cast_untold, :staff_ids, :staff_untold) do
    def cast_untold_count = cast_untold.size
    def staff_untold_count = staff_untold.size
    def anyone_untold? = cast_untold.any? || staff_untold.any?
  end
  # A show taking sign-ups (an open mic): who's registered, of how many spots.
  Signups = Data.define(:instance, :count, :capacity, :queued) do
    def form = instance.sign_up_form
  end
  Tickets = Data.define(:listing, :stats, :phase) do
    def draft? = listing.status == "draft"
    def canceled? = listing.status == "canceled" || listing.show.canceled
    def live? = phase.in?(%i[presale door])
    def sold_out? = stats.remaining == 0
  end
  # missing: the per-show roles Role Call expects on this show that no shift
  # covers (a show's own; always empty on a day's row).
  Staffing = Data.define(:shifts, :staffed, :total, :declined, :day_has_shifts, :missing) do
    def none? = shifts.empty?
    def starts_at = shifts.map(&:starts_at).min
    def ends_at = shifts.map(&:ends_at).max
    def role_names = shifts.map { |s| s.house_role&.name }.compact.uniq
    def open = [ total - staffed, 0 ].max
    def full? = total.positive? && staffed >= total && declined.zero?
  end
  Cast = Data.define(:roles_count, :assigned, :vacancies, :unnotified, :people) do
    def uncast = [ roles_count - assigned, 0 ].max
    def complete? = uncast.zero? && vacancies.empty?
  end

  attr_reader :days, :shows, :shifts, :week_finalized, :declined_this_range

  def initialize(organization:, user:, days:, shows:, show_cast:, pro_manager:)
    @organization = organization
    @user = user
    @days = days
    @shows = shows
    @show_cast = show_cast
    @pro_manager = pro_manager
    load_shifts
    load_listings
    load_signups
    load_cast
    load_told
  end

  def tickets_on? = @pro_manager && @listings.any?
  def staffing_on? = @pro_manager && @house_role_count.positive?

  # { Date => [Row] }, every day in the range present (empty days too).
  def rows_by_day
    @rows_by_day ||= begin
      by_day = shows.group_by { |s| s.date_and_time.to_date }
      days.index_with { |day| (by_day[day] || []).map { |show| row_for(show) } }
    end
  end

  def rows
    rows_by_day.values.flatten
  end

  def shows_on(day) = rows_by_day.fetch(day, []).map(&:show)

  # { Date => [Staffing] } for the shifts no show row counts: the roles that
  # aren't per show (bartender, house staff, security work the whole night,
  # not one show), and every shift on a day with no show (a private party
  # that isn't a show in CocoScout, a work day). Shifts whose times overlap
  # make one row, named after their roles and placed by its start among the
  # day's shows; a 2 PM party and the evening's crew are two rows. Nothing
  # shows twice (Tim, 2026-10-29 and 10-30). Pro managers only, like the
  # staffing chips.
  def staffing_days
    @staffing_days ||= days.each_with_object({}) do |day, out|
      day_shifts = @shifts_by_day[day] || []
      next if day_shifts.empty?

      claimed = rows_by_day[day].flat_map { |r| r.staffing&.shifts || [] }.map(&:id).to_set
      left = day_shifts.reject { |s| claimed.include?(s.id) }
      next if left.empty?

      out[day] = overlapping_groups(left).map do |group|
        stats = slot_stats(group)
        Staffing.new(shifts: group, staffed: stats[:staffed], total: stats[:total], declined: stats[:declined], day_has_shifts: true, missing: [])
      end
    end
  end

  # The day's show rows and staffing rows, in order of start time.
  def day_entries(day)
    shows = rows_by_day.fetch(day, []).map { |row| [ row.show.date_and_time, 0, row ] }
    staffing = staffing_days.fetch(day, []).map { |s| [ s.starts_at, 1, s ] }
    (staffing + shows).sort_by { |at, kind, _| [ at, -kind ] }.map(&:last)
  end

  # A day with a show, or with staffing.
  def busy?(day) = rows_by_day[day].any? || staffing_days.key?(day)

  # The range's slots: staffed of needed, and how many can't make it.
  def week_stats
    @week_stats ||= slot_stats(shifts)
  end

  def open_slots = week_stats[:total] - week_stats[:staffed]

  def staffing_draft? = staffing_on? && shifts.any? && !week_finalized

  # Shows whose cast has someone not yet told their spot.
  def unnotified_shows
    rows.select { |r| r.cast && r.cast.unnotified.positive? && !r.show.canceled }.map(&:show)
  end

  def vacancies
    @vacancies_by_show.values.flatten
  end

  private

  def row_for(show)
    Row.new(show: show, signups: signups_for(show), tickets: tickets_for(show), staffing: staffing_for(show), cast: cast_for(show),
            told: told_for(show))
  end

  # --- Sign-ups -----------------------------------------------------------

  def load_signups
    @instance_by_show = if shows.any?
      SignUpFormInstance.where(show_id: shows.map(&:id))
                        .includes(:sign_up_form, sign_up_slots: :sign_up_registrations)
                        .to_a.index_by(&:show_id)
    else
      {}
    end
    ids = @instance_by_show.values.map(&:id)
    @queued_by_instance = ids.any? ? SignUpRegistration.queued.where(sign_up_form_instance_id: ids).group(:sign_up_form_instance_id).count : {}
  end

  def signups_for(show)
    instance = @instance_by_show[show.id]
    return nil unless instance

    Signups.new(instance: instance, count: instance.registration_count, capacity: instance.total_capacity, queued: @queued_by_instance.fetch(instance.id, 0))
  end

  # --- Tickets ------------------------------------------------------------

  def load_listings
    @listings = if @pro_manager && shows.any?
      @organization.ticket_listings.where(show_id: shows.map(&:id)).includes(show: :space_rental).to_a
    else
      []
    end
    @listing_by_show = @listings.index_by(&:show_id)
    @stats = @listings.any? ? Ticketing::ListingStats.for(@listings) : {}
  end

  def tickets_for(show)
    return nil unless tickets_on?

    listing = @listing_by_show[show.id]
    return nil unless listing

    Tickets.new(listing: listing, stats: @stats.fetch(listing.id), phase: DoorTonight.phase(listing))
  end

  # --- Staffing -----------------------------------------------------------

  def load_shifts
    @house_role_count = @pro_manager ? @organization.house_roles.active.count : 0
    @per_show_roles = @pro_manager ? @organization.house_roles.active.show_specific.ordered.to_a : []
    @shifts = if staffing_on?
      @organization.shifts
                   .where(starts_at: days.first.beginning_of_day..days.last.end_of_day)
                   .includes(:house_role, :source, :shift_additional_roles, { shows: :production }, shift_assignments: { person: Manage::WeekLoaders::HEADSHOT_PRELOAD })
                   .ordered.to_a
    else
      []
    end
    @week_finalized = staffing_on? && @organization.staffing_finalizations.where(week_start: days.map(&:beginning_of_week).uniq)
                                                   .where.not(finalized_at: nil).exists?
    @declined_this_range = @shifts.flat_map { |s| s.shift_assignments.select(&:declined?) }
    # The day Staffing's week puts each shift on (WeekLoaders#staffing_day_for):
    # its show's or rental's day when that's in range, else its own start.
    @shifts_by_day = @shifts.group_by do |s|
      anchor = (s.source.try(:date_and_time) || s.source.try(:starts_at))&.to_date
      anchor && days.include?(anchor) ? anchor : s.starts_at.to_date
    end
  end

  # A show counts only its per-show roles (a booth tech): a shift of one
  # tied to that show, or tied to none and overlapping it. Roles for the
  # whole night go on the day's own row (staffing_days), never on whichever
  # show their shift happens to be tied to (Tim, 2026-10-30). No chip at all
  # when the organization has no per-show roles.
  def staffing_for(show)
    return nil unless staffing_on? && @per_show_roles.any?
    return nil if show.canceled # its row says whether the staff were told (told_for)

    day_shifts = (@shifts_by_day[show.date_and_time.to_date] || []).select { |s| s.house_role&.show_specific? }
    mine = day_shifts.select do |shift|
      covered = shift.covered_shows
      covered.any? ? covered.any? { |c| c.id == show.id } : (shift.starts_at < show.ends_at && shift.ends_at > show.date_and_time)
    end
    stats = slot_stats(mine)
    Staffing.new(shifts: mine, staffed: stats[:staffed], total: stats[:total], declined: stats[:declined],
                 day_has_shifts: day_shifts.any?, missing: missing_roles(show, mine))
  end

  # Role Call's roles for this show (when the organization has Role Call on)
  # that no shift of the show covers, by name. Like Staffing's Role Call: a
  # role scoped to another venue, or excused for this show, isn't missing.
  def missing_roles(show, mine)
    return [] unless @organization.alert_uncovered_show_roles?

    covered = mine.flat_map { |s| [ s.house_role_id ] + s.shift_additional_roles.select { |r| r.show_id.nil? || r.show_id == show.id }.map(&:house_role_id) }.to_set
    exempt = show.staffing_coverage_exempt_role_ids
    @per_show_roles.select { |r| r.include_in_role_call && (r.location_id.nil? || r.location_id == show.location_id) }
                   .reject { |r| covered.include?(r.id) || exempt.include?(r.id) }
                   .map(&:name)
  end

  # Shifts in runs whose times overlap, each run in start order.
  def overlapping_groups(shifts)
    shifts.sort_by(&:starts_at).each_with_object([]) do |shift, groups|
      if groups.any? && shift.starts_at < groups.last.map(&:ends_at).max
        groups.last << shift
      else
        groups << [ shift ]
      end
    end
  end

  def slot_stats(list)
    needing = list.select(&:needs_assignment?)
    {
      staffed: needing.sum { |s| [ s.assigned_count, s.required_count ].min },
      total: needing.sum(&:required_count),
      declined: list.sum { |s| s.shift_assignments.count(&:declined?) }
    }
  end

  # --- Telling people --------------------------------------------------------

  def load_told
    ids = @shows.map(&:id)
    @changes_by_show = ShowChange.where(show_id: ids).includes(:notices).order(:created_at).group_by(&:show_id)
    names = @changes_by_show.values.flatten.flat_map { |c| c.cast_person_ids + c.staff_person_ids }
    @people_by_id = Person.where(id: names.uniq).index_by(&:id)
  end

  # A canceled show still to come: who was told it's off (or, canceled before
  # changes were recorded, everyone on it, untold). A moved show: who's still
  # to hear, while anyone is. Staff only where Staffing is on (Pro).
  def told_for(show)
    changes = @changes_by_show[show.id] || []
    if show.canceled
      return nil if show.ends_at < Time.current

      change = changes.reverse.find { |c| c.kind == "canceled" }
      return told_from(show, change) if change

      cast = ShowChanges.cast_entries(show).map { |e| e["person_id"] }
      staff = staffing_on? ? ShowChanges.staff_entries(ShowChanges.shifts_for(show, "canceled")).map { |e| e["person_id"] }.uniq : []
      return nil if cast.empty? && staff.empty?

      Told.new(show: show, kind: "canceled", change: nil, cast_ids: cast, cast_untold: names_for(cast, preload: true),
               staff_ids: staff, staff_untold: names_for(staff, preload: true))
    else
      change = changes.reverse.find { |c| c.moved? && c.waiting? }
      change && told_from(show, change)
    end
  end

  def told_from(show, change)
    closed = change.closed_at.present?
    Told.new(show: show, kind: change.kind, change: change,
             cast_ids: change.cast_person_ids, cast_untold: closed ? [] : names_for(change.untold_cast_ids),
             staff_ids: change.staff_person_ids, staff_untold: closed ? [] : names_for(change.untold_staff_ids))
  end

  def names_for(ids, preload: false)
    people = preload ? Person.where(id: ids).index_by(&:id) : @people_by_id
    ids.filter_map { |id| people[id]&.name }
  end

  # --- Cast ---------------------------------------------------------------

  def load_cast
    ids = shows.map(&:id)
    @roles_by_show = {}
    @assignments_by_show = {}
    @notified = Set.new
    @vacancies_by_show = Hash.new { |h, k| h[k] = [] }
    return if ids.empty?

    production_ids = shows.map(&:production_id).uniq
    production_roles = Role.where(production_id: production_ids, show_id: nil).to_a.group_by(&:production_id)
    custom_roles = Role.where(show_id: ids).to_a.group_by(&:show_id)
    shows.each do |show|
      @roles_by_show[show.id] = show.use_custom_roles? ? custom_roles.fetch(show.id, []) : production_roles.fetch(show.production_id, [])
    end
    @assignments_by_show = ShowPersonRoleAssignment.where(show_id: ids).to_a.group_by(&:show_id)
    @notified = ShowCastNotification.cast_notifications.where(show_id: ids)
                                    .pluck(:show_id, :assignable_type, :assignable_id, :role_id).to_set
    RoleVacancy.active.where(show_id: ids).includes(:role).order(:created_at).each { |v| @vacancies_by_show[v.show_id] << v }
  end

  def cast_for(show)
    return nil if show.canceled # its row says whether the cast were told (told_for)

    roles = @roles_by_show.fetch(show.id, [])
    assignments = @assignments_by_show.fetch(show.id, [])
    return nil if roles.empty? && assignments.empty? && @vacancies_by_show[show.id].empty?

    unnotified = assignments.count { |a| !@notified.include?([ show.id, a.assignable_type, a.assignable_id, a.role_id ]) }
    Cast.new(roles_count: roles.sum { |r| r.quantity || 1 }, assigned: assignments.size,
             vacancies: @vacancies_by_show[show.id], unnotified: unnotified, people: @show_cast.fetch(show.id, []))
  end
end
