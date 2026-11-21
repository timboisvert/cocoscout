# frozen_string_literal: true

# A production's own page (Tim, 2026-11-08: "a production view page... a nice
# little dashboard without editing"): everything the page reads, worked out
# in one place, each part nil or empty when it doesn't apply to this
# production or this person, so the page draws nothing for it.
#
# Three kinds of reader:
#   org_manager?  the organization's owners and managers: all of it
#   manager?      a production team manager: Settings and Add a date too
#   everyone else on the production team: what the team sees, no Pro modules
#
# The coming dates are Home's rows (HomeWeek), so a date's chips read the
# same here as on Home.
class ProductionPage
  LISTED = 5          # coming dates listed
  STAFFING_REACH = 45 # days of shifts loaded from the first listed date
  FACES = 8

  # also: a second, quieter way to answer the line, as { action:, path:,
  # method: } (the casting line's "We don't cast people in it").
  NeedsDoing = Data.define(:key, :text, :detail, :action, :path, :method, :also) do
    def initialize(also: nil, **rest) = super(also: also, **rest)
  end

  attr_reader :production, :user, :organization, :dashboard, :home, :rows, :upcoming_count

  # cast_loader: Manage::WeekLoaders#build_show_cast ({ show_id => [Person] }).
  def initialize(production:, user:, dashboard:, cast_loader:)
    @production = production
    @user = user
    @organization = production.organization
    @dashboard = dashboard
    load_dates(cast_loader)
  end

  # --- Who's reading ------------------------------------------------------

  def org_manager?
    return @org_manager if defined?(@org_manager)

    @org_manager = user.superadmin? || organization.manageable_by?(user)
  end

  def pro_manager? = org_manager? && organization.on_paid_plan?
  def manager? = org_manager? || user.manager_for_production?(production)

  def course? = production.type_course?
  def contract_production? = production.type_third_party?

  # --- Dates --------------------------------------------------------------

  # The next date that's still on, as a Home row.
  def next_row = rows.find { |row| !row.show.canceled }

  def more_dates = [ upcoming_count - rows.count { |row| !row.show.canceled }, 0 ].max

  # The last date played and how many there have been, for a production
  # with nothing coming.
  def past
    @past ||= begin
      scope = production.shows.where(canceled: [ false, nil ]).where("date_and_time < ?", Time.current)
      { last: scope.maximum(:date_and_time), count: scope.count }
    end
  end

  def kind_words
    if course? then "Course"
    elsif contract_production? then "Contract production"
    else "First-party production"
    end
  end

  # --- To do (the heading never says "Needs doing") -----------------------

  def needs_doing
    @needs_doing ||= casting_items + vacancy_items + audition_items + told_items
  end

  # --- People -------------------------------------------------------------

  def team
    @team ||= production.production_permissions
                        .includes(user: { default_person: Manage::WeekLoaders::HEADSHOT_PRELOAD })
                        .order(:role, :id).to_a
  end

  def invitations
    @invitations ||= production.team_invitations.where(accepted_at: nil).order(:created_at).to_a
  end

  # The contractor's side on its live contracts: [[person, contract], ...].
  def contract_people
    @contract_people ||= if contract_production?
      headshots = Manage::WeekLoaders::HEADSHOT_PRELOAD
      production.contracts.where.not(status: %w[draft cancelled])
                .includes(contractor: { person: headshots }, contract_people: { person: headshots }).order(:id)
                .flat_map { |contract| ([ contract.contractor&.person ] + contract.contract_people.map(&:person)).compact.map { |person| [ person, contract ] } }
                .uniq { |person, _contract| person.id }
    else
      []
    end
  end

  # --- Cast and talent pool -----------------------------------------------

  def cast?
    !course? && !contract_production?
  end

  def pool_count = pool_ids.size

  def pool_people
    @pool_people ||= Person.where(id: pool_ids.first(FACES)).includes(Manage::WeekLoaders::HEADSHOT_PRELOAD).order(:name).to_a
  end

  def roles_count
    @roles_count ||= production.roles.where(show_id: nil).count
  end

  # Not set up, Casting on, or Off, with its counts (CastingStatus), for a
  # production we run casting for.
  def casting_status
    @casting_status ||= CastingStatus.new(production, pool_count: pool_count) if cast?
  end

  # The next date's answers: { show:, answered:, of: }, nil with nobody in
  # the talent pool or nothing coming in the dashboard's six weeks.
  def availability
    return nil if pool_count.zero?

    first = dashboard[:availability_summary][:shows_with_availability].first
    first && { show: first[:show], answered: first[:with_availability], of: first[:total_cast_people] }
  end

  # { signed:, total:, ... } when the production asks its performers to
  # sign an agreement and the reader is one of the organization's managers.
  def agreement
    return nil unless pro_manager? && organization.feature_available?(:agreements) && production.agreement_required?

    @agreement ||= production.agreement_roster_counts
  end

  # --- Auditions and sign-ups ---------------------------------------------

  def audition_calls = cast? ? dashboard[:open_calls][:with_auditionees] : []
  def sign_up_forms = contract_production? || course? ? [] : dashboard[:sign_up_forms]

  # --- Tickets ------------------------------------------------------------

  # What a production team member may see of sales: :full, :numbers or nil.
  def team_sales_level
    return nil if org_manager? || course?
    return @team_sales_level if defined?(@team_sales_level)

    @team_sales_level = TicketSalesAccess.team_level_for(user, production)
  end

  def tickets_box? = org_manager? && !course?

  # The dates on sale or drafted, soonest first, with their numbers.
  def ticket_listings
    @ticket_listings ||= organization.ticket_listings.where(production: production).where.not(status: "canceled").joins(:show)
                                     .where(shows: { canceled: [ false, nil ] }).where("shows.date_and_time >= ?", Time.current.beginning_of_day)
                                     .order("shows.date_and_time").includes(show: [ :location_space, :space_rental, { location: :location_spaces } ]).to_a
  end

  def ticket_stats
    @ticket_stats ||= Ticketing::ListingStats.for(ticket_listings)
  end

  def tickets_sold = ticket_stats.values.sum(&:sold_anywhere)
  def tickets_cents = ticket_stats.values.sum(&:sales_anywhere_cents)

  # --- Money --------------------------------------------------------------

  def money?
    pro_manager? && organization.feature_available?(:money) && !course? && !contract_production?
  end

  # A first-party production's money, all time (FinancialSummaryService).
  def money
    @money ||= FinancialSummaryService.new(production).summary_for_period(:all_time)
  end

  # The Money box is drawn once there's money to show: three zeros say
  # nothing (the way in stays under Go to).
  def money_box?
    money? && (money[:shows_with_data].to_i.positive? || money[:gross_revenue].to_f.nonzero? || money[:cost_of_shows].to_f.nonzero?)
  end

  # --- Contract -----------------------------------------------------------

  def contract
    return nil unless contract_production? && org_manager?

    @contract ||= production.contract
  end

  def contract_open? = organization.feature_available?(:contracts)

  # What a contract's status reads as, and its tone.
  def contract_status
    c = contract
    if c.signing_out_for_signature? then [ "Awaiting signature", :warn ]
    elsif c.signing_awaiting_send? then [ "Ready to send", :none ]
    elsif c.status_active? then [ "Active", :ok ]
    elsif c.status_completed? then [ "Completed", :none ]
    elsif c.status_cancelled? then [ "Canceled", :none ]
    else [ "Draft", :none ]
    end
  end

  # Payments the contractor still owes us, soonest first.
  def contract_payments_due
    @contract_payments_due ||= contract.contract_payments.where(direction: "incoming", status: "pending").order(:due_date).to_a
  end

  # --- Services -----------------------------------------------------------

  def service_needs
    @service_needs ||= if organization.services_available_to?(user)
      production.production_service_needs.includes(:house_service).to_a.sort_by { |need| need.house_service.name.to_s }
    else
      []
    end
  end

  # --- Course runs --------------------------------------------------------

  def runs
    @runs ||= course? ? production.course_offerings.where.not(status: %w[archived cancelled]).order(:created_at).to_a : []
  end

  # The run a course's money box shows: the one taking registrations or
  # under way, else the newest.
  def current_run = runs.find(&:open?) || runs.find(&:closed?) || runs.last

  # The current run's money (CourseOffering#financials_summary), for the
  # organization's managers; drawn once a registration has been paid.
  def course_money
    return nil unless course? && pro_manager? && current_run

    @course_money ||= current_run.financials_summary
  end

  def course_money_box?
    course_money.present? && (course_money[:gross_cents].to_i.positive? || course_money[:payout_cents].to_i.positive?)
  end

  def run_for(show)
    show.course_offering_id && runs.find { |run| run.id == show.course_offering_id }
  end

  def students(run)
    (@students ||= {})[run.id] ||= run.confirmed_registrations_count
  end

  # "Class 4 of 8": where a session falls in its run, [number, of].
  def session_number(show)
    run = run_for(show)
    return nil unless run

    ids = (@session_ids ||= {})[run.id] ||= run.sessions.pluck(:id)
    index = ids.index(show.id)
    index && [ index + 1, ids.size ]
  end

  private

  def load_dates(cast_loader)
    scope = production.shows.where("date_and_time >= ?", Time.current.beginning_of_day)
    listed = scope.includes(:production, :location_space, :space_rental, location: :location_spaces).order(:date_and_time).limit(LISTED + 12).to_a
                  .reject { |show| show.ends_at < Time.current }.first(LISTED)
    # Everything still to start, plus what's on right now.
    @upcoming_count = scope.where(canceled: [ false, nil ]).where("date_and_time >= ?", Time.current).count +
                      listed.count { |show| !show.canceled && show.date_and_time < Time.current }

    first = listed.first&.date_and_time&.to_date || Date.current
    last = [ listed.last&.date_and_time&.to_date || first, first + STAFFING_REACH ].min
    @home = HomeWeek.new(organization: organization, user: user, days: (first..last).to_a, shows: listed,
                         show_cast: cast_loader.call(listed), pro_manager: pro_manager?)
    @rows = listed.map { |show| @home.row(show) }
  end

  def pool_ids
    @pool_ids ||= if cast?
      Person.joins(:talent_pool_memberships).where(talent_pool_memberships: { talent_pool_id: production.effective_talent_pool_ids })
            .distinct.order(:name, :id).pluck(:name, :id).map(&:last)
    else
      []
    end
  end

  def day(time) = time.strftime("%a, %b %-d")

  # Dates booked at another organization (they follow its contract) in a
  # production where casting isn't set up: one line, with the two ways to
  # answer it (Tim, 2026-11-18). For the people who can answer it: the
  # production's managers. It goes once casting is set up, or once the
  # production is marked "We don't cast people in this production".
  #
  # It says "booked at", not "arrived from": a date the contractor already
  # had, matched to the contract when they connected, never arrived. Counted
  # are the dates still to come that are on; an organization that can't be
  # read is left out rather than guessed at.
  def casting_items
    return [] unless cast? && manager? && production.casting_not_set_up?

    booked = production.shows.where.not(linked_show_id: nil).where(canceled: [ false, nil ]).where("date_and_time >= ?", Time.current)
                       .includes(linked_show: { production: :organization }).to_a
    names = booked.filter_map { |show| show.followed_organization&.name }.uniq
    count = booked.count { |show| show.followed_organization }
    return [] if count.zero?

    [ NeedsDoing.new(key: "casting", text: "#{count} #{count == 1 ? 'date is' : 'dates are'} booked at #{names.to_sentence}, and casting isn't set up yet.",
                     detail: nil, action: "Set up casting", path: [ :casting_setup ], method: nil,
                     also: { action: "We don't cast people in it", path: [ :casting_off ], method: :patch }) ]
  end

  # "Sat, Nov 28 needs a Host", one line per open role.
  def vacancy_items
    return [] unless cast?

    dashboard[:open_vacancies].map do |data|
      role = data[:role]&.name.to_s
      shows = data[:is_linked] ? Array(data[:affected_shows]) : [ data[:show] ]
      dates = shows.size > 1 ? "#{day(shows.first.date_and_time)} and #{shows.size - 1} more" : day(data[:show].date_and_time)
      out = data[:invitations_count].to_i
      NeedsDoing.new(key: "vacancy", text: "#{dates} #{shows.size > 1 ? 'need' : 'needs'} #{role.match?(/\A[aeiou]/i) ? 'an' : 'a'} #{role}",
                     detail: out.positive? ? "#{out} #{'invitation'.pluralize(out)} out" : nil,
                     action: manager? ? "Fill the role" : "See the role",
                     path: [ :vacancy, data[:vacancy] ], method: nil)
    end
  end

  def audition_items
    return [] unless cast?

    # The ones this user hasn't voted on, as home and the Sign-ups page count them.
    count = AuditionsToReview.new(user: user, productions: [ production ]).total
    return [] unless count.positive?

    [ NeedsDoing.new(key: "auditions", text: "#{count} audition #{'sign-up'.pluralize(count)} to review", detail: nil,
                     action: "Review", path: [ :auditions ], method: nil) ]
  end

  # A date that moved or was canceled with people who haven't been told.
  def told_items
    return [] unless manager?

    rows.filter_map do |row|
      told = row.told
      next unless told

      untold = told.cast_untold_count + (home.staffing_on? ? told.staff_untold_count : 0)
      next unless untold.positive?

      NeedsDoing.new(key: "told", text: "#{day(row.show.date_and_time)} #{told.kind == 'moved' ? 'moved' : 'is canceled'}",
                     detail: "#{untold} #{untold == 1 ? "person hasn't" : "people haven't"} been told", action: "Tell them",
                     path: told.change ? [ :changes, told.change.batch ] : [ :tell_canceled, row.show ],
                     method: told.change ? nil : :post)
    end
  end
end
