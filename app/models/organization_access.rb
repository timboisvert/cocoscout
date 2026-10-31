# frozen_string_literal: true

# What a person can get to in an organization, module by module: none, view
# or manage (Books V1.3, plan §9.11). Owners and managers have everything.
# Anyone else on the team (company_role "viewer") is read by their grants,
# which a template fills in: Bookkeeper, Accountant, Box office, Show
# scheduler, Education manager, Marketing. A viewer with no grants keeps
# the old meaning: the free modules to read, no Pro modules.
#
#   OrganizationAccess.level(user, organization, :books)   # => "manage"
#   OrganizationAccess.allows?(user, organization, :payouts, :view)
#
# Productions keep their production team managers (ProductionPermission);
# this never looks at those. "productions" here is the Home page and the
# productions list, which everyone on the team can at least read.
class OrganizationAccess
  LEVELS = %w[none view manage].freeze
  LEVEL_RANK = { "none" => 0, "view" => 1, "manage" => 2 }.freeze

  # key, label, note, feature (nil for a free module), money (true for a
  # Money sub-module, shown indented under Money).
  MODULES = [
    { key: "productions", label: "Home and productions", note: "always at least view" },
    { key: "shows", label: "Shows and events" },
    { key: "casting", label: "Casting" },
    { key: "signups", label: "Sign-ups" },
    { key: "courses", label: "Courses" },
    { key: "documents", label: "Documents" },
    { key: "contacts", label: "Contacts" },
    { key: "ticketing", label: "Ticketing", feature: :ticketing },
    { key: "door", label: "The door", feature: :ticketing },
    { key: "mailing_lists", label: "Mailing lists", feature: :mailing_lists },
    { key: "staffing", label: "Staffing", feature: :staffing, note: "hours and schedules" },
    { key: "contracts", label: "Contracts", feature: :contracts },
    { key: "reports", label: "Reports", feature: :reports },
    { key: "settle_up", label: "Settle up and Financials", feature: :money, money: true },
    { key: "payouts", label: "Payout runs", feature: :money, money: true, note: "view means review, not send" },
    { key: "bills_invoices", label: "Bills and invoices", feature: :money, money: true },
    { key: "books", label: "Books", feature: :money, money: true },
    { key: "money_settings", label: "Money settings", feature: :money, money: true }
  ].freeze
  MODULE_KEYS = MODULES.map { |m| m[:key] }.freeze
  MONEY_MODULES = MODULES.select { |m| m[:money] }.map { |m| m[:key] }.freeze
  FREE_MODULES = MODULES.reject { |m| m[:feature] }.map { |m| m[:key] }.freeze

  # Templates fill the grid; the grants are what's stored, so a template is
  # a starting point, not a role to maintain. "manager" is company_role
  # manager (everything); "custom" is any grid.
  TEMPLATES = {
    "manager" => { label: "Manager", blurb: "Everything but the organization's own settings and billing." },
    "bookkeeper" => { label: "Bookkeeper", blurb: "All of Money: settling up, recording, bills, invoices and Books. Payout runs to review but not send. Staffing hours and Contracts to read.",
                      grants: { "productions" => "view", "shows" => "view", "contacts" => "view", "staffing" => "view", "contracts" => "view", "reports" => "view",
                                "settle_up" => "manage", "payouts" => "view", "bills_invoices" => "manage", "books" => "manage", "money_settings" => "view" } },
    "accountant" => { label: "Accountant", blurb: "All of Money to read and download. Changes nothing.",
                      grants: { "productions" => "view", "reports" => "view", "settle_up" => "view", "payouts" => "view", "bills_invoices" => "view", "books" => "view", "money_settings" => "view" } },
    "box_office" => { label: "Box office", blurb: "Ticketing, the door and Products. Shows to read.",
                      grants: { "productions" => "view", "shows" => "view", "contacts" => "view", "ticketing" => "manage", "door" => "manage" } },
    "show_scheduler" => { label: "Show scheduler", blurb: "Shows and events, Contracts and Casting. Settle up to read.",
                          grants: { "productions" => "manage", "shows" => "manage", "casting" => "manage", "contacts" => "view", "contracts" => "manage", "settle_up" => "view" } },
    "education_manager" => { label: "Education manager", blurb: "Courses and their contracts, and Sign-ups. Course money to read.",
                             grants: { "productions" => "view", "courses" => "manage", "signups" => "manage", "contacts" => "view", "contracts" => "view", "settle_up" => "view" } },
    "marketing" => { label: "Marketing", blurb: "Mailing lists, Documents and the public pages. Shows to read.",
                     grants: { "productions" => "view", "shows" => "view", "documents" => "manage", "contacts" => "view", "mailing_lists" => "manage" } },
    "custom" => { label: "Custom", blurb: "Whatever the grid says." }
  }.freeze

  # The full grid a template gives: every module, none unless the template
  # says otherwise, Home and productions never below view.
  def self.grants_for_template(template)
    base = MODULE_KEYS.index_with { "none" }
    base["productions"] = "view"
    base.merge((TEMPLATES.dig(template, :grants) || {}).slice(*MODULE_KEYS))
  end

  # Grants typed in by hand, tidied: only real modules and levels, Home and
  # productions never below view.
  def self.normalize(grants)
    out = (grants || {}).to_h.transform_keys(&:to_s).slice(*MODULE_KEYS).transform_values { |v| LEVELS.include?(v.to_s) ? v.to_s : "none" }
    out["productions"] = "view" if out["productions"].nil? || out["productions"] == "none"
    out
  end

  # The template whose grid matches these grants exactly, else "custom".
  def self.template_for(grants)
    normalized = normalize(grants)
    TEMPLATES.each_key do |t|
      next if %w[manager custom].include?(t)
      return t if grants_for_template(t) == MODULE_KEYS.index_with { |k| normalized[k] || "none" }
    end
    "custom"
  end

  def self.level(user, organization, module_key)
    return "none" if user.nil? || organization.nil?
    return "manage" if user.superadmin? || organization.owned_by?(user)

    role = role_for(user, organization)
    return "none" if role.nil?
    return "manage" if role.company_role == "manager"
    return "none" unless role.company_role == "viewer"

    key = module_key.to_s
    if role.module_grants.present?
      role.module_grants[key] || (key == "productions" ? "view" : "none")
    else
      # A viewer without grants: today's meaning. The free modules to read,
      # nothing Pro.
      FREE_MODULES.include?(key) ? "view" : "none"
    end
  end

  # True when this person's access is read from a grid: a viewer with
  # grants. Owners, managers, superadmins and old-style viewers aren't, and
  # the gate keeps today's rules for them.
  def self.governed?(user, organization)
    return false if user.nil? || organization.nil? || user.superadmin? || organization.owned_by?(user)

    role = role_for(user, organization)
    role.present? && role.company_role == "viewer" && role.module_grants.present?
  end

  def self.allows?(user, organization, module_key, level = :view)
    LEVEL_RANK[self.level(user, organization, module_key)] >= LEVEL_RANK[level.to_s]
  end

  # The Money hub and nav item: anyone with any part of Money.
  def self.money_level(user, organization)
    MONEY_MODULES.map { |m| level(user, organization, m) }.max_by { |l| LEVEL_RANK[l] } || "none"
  end

  def self.role_for(user, organization)
    if user.organization_roles.loaded?
      user.organization_roles.detect { |r| r.organization_id == organization.id }
    else
      user.organization_roles.find_by(organization_id: organization.id)
    end
  end
  private_class_method :role_for

  # Which module a manage controller belongs to, for the gate and the nav.
  # Money is split by sub-module; a Money controller not named here is the
  # hub, which any Money grant opens. Controllers not named at all are
  # ungated by module (Messages, settings for other things, the organization
  # page, which gates itself).
  MODULE_BY_CONTROLLER = {
    "manage/shows" => "shows", "manage/org_shows" => "shows", "manage/vacancies" => "shows", "manage/show_wizard" => "shows", "manage/show_changes" => "shows",
    "manage/casting" => "casting", "manage/casting_availability" => "casting", "manage/roles" => "casting", "manage/talent_pools" => "casting",
    "manage/casting_tables" => "casting", "manage/org_roles" => "casting", "manage/org_talent_pools" => "casting", "manage/org_availability" => "casting",
    "manage/casting_settings" => "casting", "manage/casting_table_wizard" => "casting",
    "manage/signups" => "signups", "manage/org_signups" => "signups", "manage/sign_up_forms" => "signups", "manage/auditions" => "signups",
    "manage/audition_cycles" => "signups", "manage/audition_requests" => "signups", "manage/audition_sessions" => "signups",
    "manage/sign_up_form_wizard" => "signups", "manage/audition_cycle_wizard" => "signups", "manage/org_auditions" => "signups", "manage/org_forms" => "signups",
    "manage/course_offerings" => "courses", "manage/course_offering_wizard" => "courses", "manage/course_settings" => "courses",
    "manage/course_money" => "courses", "manage/course_offering_payouts" => "courses", "manage/course_payout_runs" => "courses",
    "manage/org_documents" => "documents", "manage/documents" => "documents",
    "manage/directory" => "contacts", "manage/people" => "contacts", "manage/groups" => "contacts", "manage/questionnaires" => "contacts",
    "manage/ticketing" => "ticketing", "manage/ticketing_attendance" => "ticketing", "manage/ticketing_settings" => "ticketing", "manage/ticket_listings" => "ticketing",
    "manage/production_ticketings" => "ticketing", "manage/ticket_orders" => "ticketing", "manage/ticket_comps" => "ticketing", "manage/ticket_taxes" => "ticketing",
    "manage/ticket_offers" => "ticketing", "manage/ticket_offer_wizard" => "ticketing", "manage/ticket_passes" => "ticketing", "manage/ticket_products" => "ticketing",
    "manage/ticket_sales_viewers" => "ticketing", "manage/short_links" => "ticketing", "manage/ticket_gift_certificates" => "ticketing",
    "manage/ticket_waitlists" => "ticketing", "manage/ticket_group_bookings" => "ticketing",
    "manage/seat_charts" => "ticketing", "manage/ticket_seat_maps" => "ticketing", "manage/ticket_memberships" => "ticketing",
    "manage/mailing_lists" => "mailing_lists", "manage/mailing_list_settings" => "mailing_lists", "manage/list_followers" => "mailing_lists",
    "manage/segments" => "mailing_lists", "manage/follower_emails" => "mailing_lists",
    "manage/contracts" => "contracts", "manage/contract_settings" => "contracts", "manage/contract_templates" => "contracts", "manage/contract_signatures" => "contracts",
    "manage/contract_payments" => "contracts", "manage/contract_wizard" => "contracts", "manage/contract_documents" => "contracts",
    "manage/contract_appendixes" => "contracts", "manage/space_rentals" => "contracts", "manage/contractors" => "contracts",
    "manage/reports" => "reports",
    "manage/money_financials" => "settle_up", "manage/show_financials" => "settle_up", "manage/production_expenses" => "settle_up", "manage/expense_items" => "settle_up",
    "manage/settlement_days" => "settle_up", "manage/ticket_outside_sales" => "settle_up",
    "manage/money_payouts" => "payouts", "manage/show_payouts" => "payouts", "manage/payout_calculations" => "payouts", "manage/payout_calculation_wizard" => "payouts",
    "manage/payout_batches" => "payouts", "manage/advances" => "payouts",
    "manage/money_incoming" => "bills_invoices", "manage/bills" => "bills_invoices", "manage/invoices" => "bills_invoices",
    "manage/books" => "books", "manage/ticket_balance" => "books", "manage/money_records" => "books", "manage/bank_statements" => "books",
    "manage/books_statements" => "books", "manage/books_taxes" => "books", "manage/money_files" => "books",
    "manage/money_settings" => "money_settings"
  }.freeze

  def self.module_for_controller(controller_path)
    return "staffing" if controller_path.start_with?("manage/staffing")
    return "money" if controller_path == "manage/money"

    MODULE_BY_CONTROLLER[controller_path]
  end
end
