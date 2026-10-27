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
  Row = Data.define(:show, :signups, :tickets, :staffing, :cast)
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
  Staffing = Data.define(:shifts, :staffed, :total, :declined, :day_has_shifts) do
    def none? = shifts.empty?
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
    Row.new(show: show, signups: signups_for(show), tickets: tickets_for(show), staffing: staffing_for(show), cast: cast_for(show))
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
    @shifts = if staffing_on?
      @organization.shifts
                   .where(starts_at: days.first.beginning_of_day..days.last.end_of_day)
                   .includes(:house_role, :source, { shows: :production }, shift_assignments: { person: Manage::WeekLoaders::HEADSHOT_PRELOAD })
                   .ordered.to_a
    else
      []
    end
    @week_finalized = staffing_on? && @organization.staffing_finalizations.where(week_start: days.map(&:beginning_of_week).uniq)
                                                   .where.not(finalized_at: nil).exists?
    @declined_this_range = @shifts.flat_map { |s| s.shift_assignments.select(&:declined?) }
    @shifts_by_day = @shifts.group_by { |s| (s.source.try(:date_and_time) || s.starts_at).to_date }
  end

  # A shift counts for a show when it's tied to that show, or (an evening
  # shift tied to none) when it overlaps the show.
  def staffing_for(show)
    return nil unless staffing_on?

    day_shifts = @shifts_by_day[show.date_and_time.to_date] || []
    mine = day_shifts.select do |shift|
      covered = shift.covered_shows
      covered.any? ? covered.any? { |c| c.id == show.id } : (shift.starts_at < show.ends_at && shift.ends_at > show.date_and_time)
    end
    stats = slot_stats(mine)
    Staffing.new(shifts: mine, staffed: stats[:staffed], total: stats[:total], declined: stats[:declined], day_has_shifts: day_shifts.any?)
  end

  def slot_stats(list)
    needing = list.select(&:needs_assignment?)
    {
      staffed: needing.sum { |s| [ s.assigned_count, s.required_count ].min },
      total: needing.sum(&:required_count),
      declined: list.sum { |s| s.shift_assignments.count(&:declined?) }
    }
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
    roles = @roles_by_show.fetch(show.id, [])
    assignments = @assignments_by_show.fetch(show.id, [])
    return nil if roles.empty? && assignments.empty? && @vacancies_by_show[show.id].empty?

    unnotified = assignments.count { |a| !@notified.include?([ show.id, a.assignable_type, a.assignable_id, a.role_id ]) }
    Cast.new(roles_count: roles.sum { |r| r.quantity || 1 }, assigned: assignments.size,
             vacancies: @vacancies_by_show[show.id], unnotified: unnotified, people: @show_cast.fetch(show.id, []))
  end
end
