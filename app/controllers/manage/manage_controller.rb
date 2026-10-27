# frozen_string_literal: true

module Manage
  # Under ApplicationController since V1.1 (it was ActionController::Base):
  # Manage gets activity tracking and the app's layout (resolve_layout), now
  # that production mode opens inside the app for generation-2 builds.
  class ManageController < ApplicationController
    include Manage::PaidFeatureGate
    include Manage::WeekLoaders
    include OrganizationContext

    # My's own trackers; Manage keeps its own (track_last_dashboard,
    # show_manage_sidebar).
    skip_before_action :track_my_dashboard
    skip_before_action :show_my_sidebar

    # before_action :hide_sidebar
    before_action :set_current_organization, if: -> { Current.user.present? }
    before_action :set_current_production, if: -> { Current.user.present? }
    # NOTE: no `except:` here. `except:` matches by action name across ALL
    # subclasses, so exempting :index would (wrongly) let every manage controller's
    # index run with no organization and blow up on Current.organization.*. The
    # dashboard's own index/welcome self-handle a missing org — that's exempted
    # inside the method by checking for the base controller specifically.
    before_action :require_current_organization, if: lambda {
      Current.user.present?
    }
    before_action :ensure_user_has_access_to_company, if: lambda {
      Current.user.present? && Current.organization.present?
    }, except: %i[index]
    before_action :ensure_user_has_access_to_production, if: -> { Current.user.present? },
                  except: %i[index]
    # Pro-tier gate — runs after the org is loaded and access is confirmed.
    before_action :require_paid_feature!, if: -> { Current.user.present? }

    before_action :note_mode_switch
    before_action :track_last_dashboard
    before_action :show_manage_sidebar

    def index
      # Explicitly ensure cookie is set before any redirect
      track_last_dashboard

      # Redirect to organization selection if no organization is set
      unless Current.organization
        # Clear any stale intent — user navigated to /manage generically
        session.delete(:manage_onboarding_intent)
        redirect_to select_organization_path and return
      end

      # Build org-level home page data (filtered by user access). Preload what
      # the dashboard payloads and production cards read per production, so a
      # page of productions doesn't query each one individually.
      @productions = Current.user.accessible_productions.order(:name).includes(
        { audition_cycles: :audition_requests },
        :talent_pools,
        { talent_pool_shares: :talent_pool },
        { posters: { image_attachment: :blob } }
      )
      @production_dashboards = DashboardService.generate_all(@productions)

      # What the dashboards say across every production: the open audition
      # calls, the live sign-up forms (soonest next event first) and the open
      # vacancies, for the status bar.
      @all_open_calls, @all_sign_up_forms, @all_open_vacancies = [], [], []
      @productions.each do |production|
        dashboard = @production_dashboards[production.id] or next
        dashboard[:open_calls][:with_auditionees].each { |c| @all_open_calls << c.merge(production: production) }
        dashboard[:sign_up_forms].each { |f| @all_sign_up_forms << f.merge(production: production) }
        dashboard[:open_vacancies].each { |v| @all_open_vacancies << v.merge(production: production) }
      end
      @total_audition_signups = @all_open_calls.sum { |c| c[:auditionee_count] }
      @all_sign_up_forms.sort_by! { |f| f[:instance]&.show&.date_and_time || 100.years.from_now }

      # The week, show by show (Design B, Tim 2026-10-27): seven days from
      # the week's Monday, or three days from the day asked for (?days=3,
      # remembered). A phone works one day at a time (?day=).
      @home_days = params[:days].present? ? (params[:days].to_s == "3" ? 3 : 7) : (session[:home_days] == "3" ? 3 : 7)
      session[:home_days] = @home_days.to_s if params[:days].present?
      requested_day = parse_day(params[:day])
      if @home_days == 3
        @selected_day = requested_day || Date.current
        @range = (@selected_day..(@selected_day + 2))
        @week_start = @selected_day.beginning_of_week
      else
        @week_start = requested_day ? requested_day.beginning_of_week : parse_week_start(params[:week_start])
        @range = (@week_start..(@week_start + 6))
      end
      @week_end = @week_start + 6
      shows = shows_in_range(@range, productions: @productions, canceled: true)
      @selected_day ||= requested_day ||
        (@range.cover?(Date.current) ? Date.current : nil) ||
        shows.first&.date_and_time&.to_date || @range.first
      pro_manager = Current.organization.on_paid_plan? && (Current.user.superadmin? || Current.organization.manageable_by?(Current.user))
      @home = HomeWeek.new(organization: Current.organization, user: Current.user, days: @range.to_a,
                           shows: shows, show_cast: build_show_cast(shows), pro_manager: pro_manager)
      @calendar_months = calendar_months_around(@week_start)
      @show_dates = calendar_show_dates(@calendar_months.first.beginning_of_week, @calendar_months.last.end_of_month.end_of_week, productions: @productions)
      @week_statuses = @home.staffing_on? ? calendar_week_statuses(@calendar_months.first.beginning_of_week, @calendar_months.last.end_of_month.end_of_week) : {}


      # The money and hours waiting, for the managers who handle them on Pro.
      if pro_manager
        todo = MoneyTodoService.new(user: Current.user, organization: Current.organization, row_limit: 0)
        @home_attention = { financials: todo.financials.count.to_i, payouts: todo.payouts.count.to_i, payouts_amount: todo.payouts.amount,
                            hours: Current.organization.staff_time_entries.pending.count }
      end
      @home_status = home_status_items(pro_manager)

      render "home"
    end

    # The status bar ("Needs attention", on every width): one pill per thing
    # waiting, only when it has something in it. Each is { text:, tone:,
    # action: { text:, path: | modal: }, key: }. Tones: :red (someone's
    # missing), :amber (something open), :pink (waiting on you), :gray.
    def home_status_items(pro_manager)
      items = []
      v = @all_open_vacancies.size
      if v.positive?
        items << { key: "vacancies", tone: :red, text: "#{v} open #{'vacancy'.pluralize(v)}",
                   action: v == 1 ? { text: "Review", path: manage_casting_vacancy_path(@all_open_vacancies.first[:production], @all_open_vacancies.first[:vacancy]) }
                                  : { text: "Review", modal: "home-vacancies" } }
      end
      if @total_audition_signups.positive?
        items << { key: "signups", tone: :pink, text: "#{@total_audition_signups} audition #{'sign-up'.pluralize(@total_audition_signups)} to review",
                   action: { text: "Review", path: manage_signups_path } }
      end
      if (form = @all_sign_up_forms.first) && form[:instance]&.show
        count = form[:instance].registration_count || 0
        items << { key: "registrations", tone: :pink, text: "#{count} registered for #{form[:instance].show.date_and_time.strftime('%A')}'s #{form[:form].name}",
                   action: { text: "Sign-ups", path: manage_signups_form_path(form[:production], form[:form]) } }
      end
      if @home.staffing_on?
        words = []
        words << "Staffing is a draft" if @home.staffing_draft?
        d = @home.declined_this_range.size
        words << "#{d} can't make it" if d.positive?
        words << "#{@home.open_slots} open #{'slot'.pluralize(@home.open_slots)}" if words.empty? && @home.open_slots.positive?
        if words.any?
          items << { key: "staffing", tone: d.positive? ? :red : :amber, text: words.join(" · "),
                     action: { text: "Scheduling", path: manage_staffing_scheduling_path(week_start: @week_start.to_s) } }
        end
      end
      if @home.tickets_on?
        TicketingDashboard.new(Current.organization).alerts.each_with_index do |alert, i|
          first = alert.actions.first
          items << { key: "ticketing-#{i}", tone: alert.tone == :amber ? :amber : :pink, text: alert.headline,
                     action: first && { text: first[:text], path: first[:path] } }
        end
      end
      if (n = @home.unnotified_shows.size).positive?
        items << { key: "notify", tone: :amber, text: n == 1 ? "#{@home.unnotified_shows.first.production&.name}'s cast hasn't been notified" : "#{n} shows' cast not notified yet",
                   action: { text: "Casting", path: manage_casting_path } }
      end
      if @home_attention
        a = @home_attention
        items << { key: "financials", tone: :gray, text: "#{a[:financials]} #{'show'.pluralize(a[:financials])} that need financials", action: { text: "Financials", path: manage_money_financials_path } } if a[:financials].positive?
        items << { key: "pay", tone: :pink, text: "#{helpers.number_to_currency(a[:payouts_amount])} to pay", action: { text: "Pay people", path: manage_money_payouts_path } } if a[:payouts].positive?
        items << { key: "hours", tone: :gray, text: "#{a[:hours]} #{'hour'.pluralize(a[:hours])} to approve", action: { text: "Approve", path: manage_staffing_timesheets_path } } if a[:hours].positive?
      end
      if pro_manager && Current.organization.feature_available?(:contracts)
        c = Current.organization.contracts.where(signing_state: "out_for_signature").count
        items << { key: "contracts", tone: :gray, text: "#{c} #{'contract'.pluralize(c)} out for signature", action: { text: "Contracts", path: manage_contracts_path } } if c.positive?
      end
      items
    end

    def ensure_user_is_manager
      # Check if we're in a production-specific context
      production = instance_variable_get(:@production) || Current.production

      if production
        # Check production-specific permission
        unless Current.user&.manager_for_production?(production)
          redirect_to manage_path, notice: "You do not have permission to access that page."
        end
      else
        # Fall back to checking default role for production company
        redirect_to manage_path, notice: "You do not have permission to access that page." unless Current.user&.manager?
      end
    end

    def ensure_user_is_global_manager
      # Only check global manager role, not production-specific permissions
      # Used for production-company level resources (people, team, locations)
      return if Current.user&.manager?

      redirect_to manage_path, notice: "You do not have permission to access that page."
    end

    # Gate for features still restricted to superadmins (e.g. Staffing, pre-launch).
    def ensure_user_is_superadmin
      return if Current.user&.superadmin?

      redirect_to manage_path, notice: "That area isn't available yet."
    end

    # Gate for org owner/manager-only areas (e.g. Staffing). Superadmins always pass.
    def ensure_org_owner_or_manager
      return if Current.user&.superadmin?
      return if Current.organization&.manageable_by?(Current.user)

      redirect_to manage_path, notice: "You do not have permission to access that page."
    end

    # A link (an email, a push, a bookmark) brought someone from My into
    # production mode: the page says so, with Exit (V1.1 plan §0a; Tim kept
    # Exit, 2026-10-20). Only a full page load, never a frame or a fetch.
    def note_mode_switch
      return unless Current.user && request.get? && request.format.html? && request.headers["Turbo-Frame"].blank?
      return unless NativeAppVersion.production_mode?(request.user_agent)

      # Or an opener (a message, a notification) just switched the organization
      # or the mode for this page: say so, once (Tim, 2026-10-21: with Don't
      # ask again there'd be no other sign).
      @switched_to = flash[:switched_to].presence
      @switched_into_production_mode = Current.organization.present? && (@switched_to.present? || last_mode == "my")
    end

    def track_last_dashboard
      return unless Current.user.present? && real_page_load?
      # Someone with no organization (a performer who tapped into producer
      # setup) must keep landing on My at sign-in, or every login drops them
      # back into setup with no way out.
      return unless Current.organization || Current.user.accessible_organizations.exists?

      last_dashboard_prefs = cookies.encrypted[:last_dashboard]
      # Reset if it's an old string value instead of a hash
      last_dashboard_prefs = {} unless last_dashboard_prefs.is_a?(Hash)
      last_dashboard_prefs[Current.user.id.to_s] = "manage"
      cookies.encrypted[:last_dashboard] = { value: last_dashboard_prefs, expires: 1.year.from_now }
      remember_mode("manage")
    end

    def ensure_user_has_access_to_company
      # Ensure user has at least some role/access to the current production company
      return if Current.user&.has_access_to_current_company?

      redirect_to my_dashboard_path, alert: "You do not have access to this production company."
    end

    def ensure_user_has_access_to_production
      # Ensure the user is allowed to open the production in context. Uses
      # can_access_production? (not accessible_productions) so archived productions
      # remain openable by managers/viewers — otherwise a stale/archived selection
      # in Current.production would bounce them off org-level pages too.
      production = instance_variable_get(:@production) || Current.production
      return unless production

      return if Current.user.can_access_production?(production)

      redirect_to manage_productions_path, alert: "You do not have access to this production."
    end

    def check_production_access
      # Explicit check for @production after it's been set in child controller
      return if Current.user.can_access_production?(@production)

      redirect_to manage_productions_path, alert: "You do not have access to this production."
    end

    private

    def show_manage_sidebar
      @show_manage_sidebar = true
    end

    def show_manage_header_only
      @show_manage_header_only = true
    end

    def require_current_organization
      # The org-level dashboard (this base controller's own index) handles a
      # missing org itself — the org picker. Subclasses (contracts, casting, …)
      # must NOT be let through, or they crash on a nil org (e.g. while
      # impersonating a contractor who has no organization).
      return if instance_of?(Manage::ManageController) && action_name == "index"
      return if controller_name == "organizations" && %w[new create index show].include?(action_name)
      return if controller_name == "select"
      # Producer setup exists precisely for users who have no organization yet.
      return if controller_name == "producer_setup"

      return if Current.organization

      # Store the user's intended destination so we can redirect back after org setup.
      # Only store specific deep-link paths — not the generic /manage landing page,
      # which would create a misleading "you were trying to do X" context.
      # Explicitly check GET (Rails routes HEAD like GET, but request.get? is false
      # on HEAD — being explicit makes the intent obvious and Brakeman happy).
      if request.get? || request.head?
        if request.fullpath == manage_path || request.fullpath == "#{manage_path}/"
          session.delete(:manage_onboarding_intent)
        else
          session[:manage_onboarding_intent] = request.fullpath
        end
      end

      redirect_to select_organization_path and return
    end

    def redirect_to_intent_or(fallback_path, **options)
      intent = session.delete(:manage_onboarding_intent)
      redirect_to(intent || fallback_path, **options)
    end

    # Guarantee the current user has a Person and that it belongs to the given
    # organization. Shared by org creation and producer setup.
    def ensure_person_in_organization!(organization)
      if Current.user.person.nil?
        person = Person.create!(
          email: Current.user.email_address,
          first_name: Current.user.email_address.split("@").first.titleize,
          last_name: ""
        )
        Current.user.update(person: person)
      end

      organization.people << Current.user.person unless organization.people.include?(Current.user.person)
    end

    # Shared data fetchers for use across controllers
    def fetch_locations
      Rails.cache.fetch(locations_cache_key, expires_in: 10.minutes) do
        Current.organization.locations.order(:created_at).to_a
      end
    end

    def locations_cache_key
      max_updated = Current.organization.locations.maximum(:updated_at)
      [ "locations_v1", Current.organization.id, max_updated ]
    end

    def fetch_team_members
      Rails.cache.fetch(team_cache_key, expires_in: 10.minutes) do
        members = Current.organization.users
                         .joins(:organization_roles)
                         .includes(:default_person, :organization_roles)
                         .where(organization_roles: { organization_id: Current.organization.id,
                                                      company_role: %w[manager viewer member] })
                         .distinct
        members.sort_by { |user| user == Current.user ? [ 0, "" ] : [ 1, user.email_address.downcase ] }
      end
    end

    def team_cache_key
      max_role_updated = OrganizationRole.where(organization: Current.organization).maximum(:updated_at)
      max_user_updated = Current.organization.users.maximum(:updated_at)
      [ "team_members_v1", Current.organization.id, Current.user.id, max_role_updated, max_user_updated ]
    end

    # Helper for child controllers to safely find production
    # Returns true if production was found, false if redirected
    # Also syncs Current.production and session when production is found from URL
    def find_production_or_redirect(production_id)
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return false
      end

      @production = Current.organization.productions.find_by(id: production_id)
      unless @production
        redirect_to manage_productions_path, alert: "Production not found."
        return false
      end

      # Sync Current.production and session with the URL-based production
      sync_current_production(@production)
      true
    end

    # Syncs Current.production and session to match the given production
    # Call this after setting @production from URL params
    def sync_current_production(production)
      return unless production && Current.user && Current.organization

      Current.production = production
      session[:current_production_id_for_organization] ||= {}
      session[:current_production_id_for_organization]["#{Current.user.id}_#{Current.organization.id}"] = production.id

      # Feed the production picker's cross-device "recently used" list.
      Current.user.touch_recent_production(production.id)
    end
  end
end
