# frozen_string_literal: true

module Manage
  # Gates the Production-Company-only management modules. Included once in
  # Manage::ManageController; controllers are mapped to a feature by their
  # controller_path. Producer-plan modules (Shows, Casting, Availability, basic
  # Sign-ups, Messages, Contacts, Documents, Courses) aren't in the map and pass
  # through untouched. Access is decided by the org's plan via
  # Organization#feature_available?.
  module PaidFeatureGate
    extend ActiveSupport::Concern

    # controller_path => Organization::PAID_FEATURES symbol.
    # Staffing is matched by the "manage/staffing" prefix (see #required_paid_feature).
    FEATURE_BY_CONTROLLER = {
      # Money
      "manage/money" => :money,
      "manage/money_financials" => :money,
      "manage/money_payouts" => :money,
      "manage/show_payouts" => :money,
      "manage/show_financials" => :money,
      "manage/contracts" => :money,
      "manage/contract_settings" => :money,
      "manage/contract_payments" => :money,
      "manage/contract_wizard" => :money,
      "manage/contract_documents" => :money,
      "manage/contractors" => :money,
      "manage/payout_schemes" => :money,
      "manage/payout_batches" => :money,
      "manage/advances" => :money,
      # Reports
      "manage/reports" => :reports,
      # Auditions (both in-person and video formats)
      "manage/auditions" => :auditions,
      "manage/audition_cycles" => :auditions,
      "manage/audition_cycle_wizard" => :auditions,
      "manage/audition_requests" => :auditions,
      "manage/audition_sessions" => :auditions,
      "manage/audition_email_assignments" => :auditions,
      # Casting Table
      "manage/casting_tables" => :casting_table,
      "manage/casting_table_wizard" => :casting_table,
      # Performer agreements
      "manage/agreement_templates" => :agreements
    }.freeze

    # What every Pro plan includes, shown as reinforcement on each upgrade screen.
    PRO_INCLUDES = [
      "Unlimited productions and shows/events",
      "Money: financials, payouts, contracts & advances",
      "Staffing, in-person & video Auditions, and Casting Tables",
      "Company-wide Reports",
      "Everything in Producer, with no monthly limits"
    ].freeze

    # Rich, sales-oriented copy for each locked module. Shown in the upgrade modal
    # (and as a full-page fallback). Keyed by the PAID_FEATURES symbols.
    #   name        – module name
    #   icon        – shared/module_header_icon key
    #   headline    – punchy benefit-led headline
    #   subhead     – one-sentence value statement
    #   description – short paragraph framing the module
    #   capabilities– [{ title:, body: }] concrete things you can do
    #   outcome     – the "why it matters" payoff line
    FEATURE_DETAILS = {
      money: {
        name: "Money & Payments",
        icon: "dollar-sign",
        headline: "Run the money side of your productions with confidence",
        subhead: "Full production accounting and performer payouts in one connected place, priced fairly: $3/month per performer, only in the months you actually pay them.",
        description: "Money turns show financials, contracts, advances, and payouts into a single system that always ties out — and pays performers straight to their bank. No more spreadsheets, guesswork, or wondering who still needs to get paid. Built by performers and producers who were tired of paying to move their own money.",
        capabilities: [
          { title: "Show & production financials", body: "Record ticket and other revenue per show and watch it roll up by production and time period." },
          { title: "Performer payouts", body: "Build reusable payout schemes, calculate each performer's split automatically, and pay them straight to their bank in one click." },
          { title: "Fair, per-active pricing", body: "Just $3/month per performer — and only in months you actually pay them. Unlimited payout runs included; a performer you don't pay that month costs nothing." },
          { title: "Contracts & advances", body: "Track third-party contracts and revenue shares, and issue performer advances that recover automatically from future payouts." }
        ],
        outcome: "Close every show knowing exactly what came in, what went out, and who's been paid — for $3 a performer, only when you pay them."
      },
      staffing: {
        name: "Staffing",
        icon: "users",
        headline: "Run your team — schedule, manage, and pay them — without the chaos",
        subhead: "Availability, shifts, onboarding, and payments in one workspace, priced fairly: $5/month per staff member, only in the months they actually work.",
        description: "Staffing gives you everything you need to run the people behind the show: who's working, when, what they're owed, and the paperwork to keep it all above board. Built by performers and producers who were tired of paying per head for people who weren't even working that month.",
        capabilities: [
          { title: "Staff availability & work shifts", body: "Collect availability and build shift schedules that fit each event, venue, and role." },
          { title: "Onboarding & org charts", body: "Onboard new staff Gusto-style and map who reports to whom." },
          { title: "Fair, per-active pricing", body: "Just $5/month per staff member — and only in months they're scheduled to work. Nobody working this month? You pay nothing for them." },
          { title: "Pay your staff", body: "Pay staff straight to their bank as often as you like — unlimited payouts are included in the $5." },
          { title: "Tax forms", body: "Generate the tax forms you need — W-9, 1099-NEC, 1096, and more." }
        ],
        outcome: "Keep your team scheduled, paid, and compliant — without leaving CocoScout, and without paying for people who aren't working."
      },
      auditions: {
        name: "Auditions",
        icon: "user-group",
        headline: "Run in-person and video auditions from first call to final cast",
        subhead: "Collect submissions, schedule sessions, review, vote, and notify — in one flow.",
        description: "Auditions handles the entire casting funnel. Put out a call, collect video submissions or book live audition slots, review as a team, and move your favorites straight into casting.",
        capabilities: [
          { title: "Video audition submissions", body: "Let performers submit video auditions online, organized by cycle and role." },
          { title: "In-person audition sessions", body: "Publish available slots and let auditionees book the time that works for them." },
          { title: "Team review & voting", body: "Invite reviewers, leave notes, and vote to reach a decision together." },
          { title: "Automatic notifications", body: "Invite, remind, and follow up with auditionees automatically." },
          { title: "Straight into casting", body: "Move the people you love directly into your talent pool and casting board." }
        ],
        outcome: "Cast faster, with a clear record of everyone who auditioned and why you chose them."
      },
      casting_table: {
        name: "Casting Table",
        icon: "clipboard-list",
        headline: "Cast a whole run of shows at once on one visual board",
        subhead: "See every role across every show in a single grid and fill them without conflicts.",
        description: "The Casting Table is built for producers juggling many shows at once. Lay out your entire schedule, drag performers into open slots, and instantly see collisions and gaps before they become problems.",
        capabilities: [
          { title: "One grid, every show", body: "See all your roles across all your shows and events in a single view." },
          { title: "Drag-and-drop casting", body: "Assign performers to open slots in seconds and rearrange as plans change." },
          { title: "Conflict & vacancy detection", body: "Spot double-bookings and unfilled roles instantly, before they cost you." },
          { title: "Finalize & notify", body: "Lock in your cast and notify everyone at once when the board is ready." }
        ],
        outcome: "Cast a season in an afternoon instead of chasing a dozen separate spreadsheets."
      },
      reports: {
        name: "Reports",
        icon: "chart-bar",
        headline: "Understand your whole company at a glance",
        subhead: "Revenue, payouts, participation, and programming — turned into clear reports.",
        description: "Reports pulls data from across CocoScout into answers you can act on: what's making money, who's performing most, and where your programming is headed.",
        capabilities: [
          { title: "Revenue by production & over time", body: "See which productions drive revenue and how it trends month over month." },
          { title: "Payouts & course revenue", body: "Track what you've paid out, what's outstanding, and course revenue net of fees." },
          { title: "Cast participation", body: "See who's in the most shows and how your roster is being used." },
          { title: "Events & programming", body: "Break down your calendar by event type and status to plan what's next." }
        ],
        outcome: "Make booking, budgeting, and casting decisions from real numbers — not gut feel."
      },
      agreements: {
        name: "Performer Agreements",
        icon: "clipboard-list",
        headline: "Get every performer on the same page — and on the record",
        subhead: "Send agreements, collect e-signatures, and always know who's signed.",
        description: "Performer Agreements turns your code of conduct, payment terms, and policies into a reusable template performers sign online. Send it manually or automatically when someone joins your talent pool, and track it all from one roster.",
        capabilities: [
          { title: "Reusable agreement templates", body: "Write your terms once with merge fields for production, performer, and date, and reuse them across every production." },
          { title: "Online e-signatures", body: "Performers review and sign in-app; each signature is snapshotted with a timestamp for your records." },
          { title: "Manual or automatic sending", body: "Send on your schedule, or have the agreement go out the moment someone is added to a talent pool." },
          { title: "Signed / awaiting / not-sent roster", body: "See at a glance who has signed, who's been asked, and who still needs it — and resend in a click." }
        ],
        outcome: "Cast with confidence, knowing everyone has agreed to your terms in writing."
      }
    }.freeze

    # NOTE: the before_action is registered explicitly in Manage::ManageController
    # (after set_current_organization) so it runs once the org is loaded.

    private

    # The Pro feature this request requires, or nil if it's a free module.
    def required_paid_feature
      return :staffing if controller_path.start_with?("manage/staffing")

      FEATURE_BY_CONTROLLER[controller_path]
    end

    def require_paid_feature!
      feature = required_paid_feature
      return if feature.nil?
      return if Current.organization.nil?
      # Gate by the organization's plan for everyone — superadmins included — so
      # what's locked in the nav is actually locked. Superadmins who need a paid
      # feature can comp the org to Pro.
      return if Current.organization.feature_available?(feature)

      respond_to do |format|
        format.json do
          render json: { error: "upgrade_required", feature: feature }, status: :payment_required
        end
        format.html do
          @paywall_feature = feature
          @paywall = FEATURE_DETAILS[feature] || { name: feature.to_s.humanize, tagline: "", bullets: [] }
          render template: "manage/billing/feature_paywall", status: :payment_required
        end
        format.any { redirect_to org_billing_tab_path }
      end
    end

    # Canonical billing location: the org's "Billing & Plan" tab (index 4).
    def org_billing_tab_path
      manage_organization_path(Current.organization, anchor: "tab-4")
    end

    # before_action for Show-creation actions: redirect free orgs that have hit
    # the monthly event cap to billing. The Show model validation is the hard
    # backstop; this just gives a friendlier redirect for the common paths.
    # Reads the event's target date from the submitted params.
    def enforce_free_event_limit
      return if Current.organization.nil?
      return if Current.organization.on_paid_plan?

      target_date = event_limit_target_date
      return if target_date.nil?
      return unless Current.organization.at_event_limit?(target_date)

      respond_to do |format|
        format.json do
          render json: { error: "event_limit_reached", limit: Organization::FREE_MONTHLY_EVENT_LIMIT },
                 status: :payment_required
        end
        format.any { redirect_to org_billing_tab_path, notice: event_limit_notice }
      end
    end

    def event_limit_target_date
      raw = params.dig(:show, :recurrence_start_datetime).presence || params.dig(:show, :date_and_time).presence
      return nil if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError
      nil
    end

    def event_limit_notice
      "You've reached the Producer plan limit of #{Organization::FREE_MONTHLY_EVENT_LIMIT} events this month. " \
        "Upgrade to Pro for unlimited events."
    end

    # before_action for production-creation actions: redirect Producer-plan orgs
    # that already run their allotted production to billing. The Production model
    # validation is the hard backstop.
    def enforce_free_production_limit
      return if Current.organization.nil?
      return unless Current.organization.at_production_limit?

      respond_to do |format|
        format.json do
          render json: { error: "production_limit_reached", limit: Organization::FREE_PRODUCTION_LIMIT },
                 status: :payment_required
        end
        format.any { redirect_to org_billing_tab_path, notice: production_limit_notice }
      end
    end

    def production_limit_notice
      "The Producer plan includes one production. " \
        "Upgrade to Pro to run unlimited productions."
    end
  end
end
