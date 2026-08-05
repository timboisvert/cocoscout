# frozen_string_literal: true

# Single source of truth for the dashboard navigations. Both the desktop sidebar
# (shared/navigation/_sidebar_nav) and the mobile app-grid
# (shared/navigation/_mobile_grid_nav) render from these item lists, so there is
# one place that decides *who sees what* in each context.
#
# IMPORTANT: the visibility rules here are ported verbatim from the old
# per-context nav partials and must keep behaving exactly the same.
module NavigationHelper
  # Ordered sections for a dashboard context. Each section:
  #   { label: nil | String, items: [item, ...] }
  # Each item:
  #   { label:, path:, icon:, active:, badge: (int), locked: (bool), feature: }
  def dashboard_nav_sections(context)
    return [] unless Current.user

    case context.to_sym
    when :production then production_nav_sections
    when :talent then talent_nav_sections
    when :account then account_nav_sections
    when :superadmin then superadmin_nav_sections
    else []
    end
  end

  # SVG path `d` for a nav icon key (used by the mobile grid tiles).
  def nav_icon_path(key)
    NAV_ICON_PATHS[key.to_s] || NAV_ICON_PATHS["dot"]
  end

  private

  # --- Production (org-scoped) ---------------------------------------------
  # Mirrors shared/navigation/_manage exactly.
  def production_nav_sections
    return [] unless Current.organization.present?

    has_team_access = %w[manager viewer].include?(Current.user.default_role) ||
      Current.user.accessible_productions.where(organization: Current.organization).any? { |p| Current.user.role_for_production(p).present? }

    unless has_team_access
      return [ { label: nil, items: [
        { label: "Sign-ups", path: manage_signups_path, icon: "signups",
          active: %w[signups org_signups sign_up_forms auditions audition_cycles audition_requests audition_sessions].include?(controller_name) }
      ] } ]
    end

    on_paid_plan = Current.organization&.on_paid_plan?

    free_items = [
      { label: "Home", path: manage_path, icon: "home", active: controller_name == "manage" && action_name == "index" },
      { label: "Messages", path: manage_messages_path, icon: "messages", active: controller_name == "messages",
        badge: Current.user&.unread_message_count_for_org(Current.organization).to_i },
      { label: "Shows & Events", path: manage_shows_path, icon: "shows",
        active: %w[shows org_shows vacancies show_wizard].include?(controller_name) },
      { label: "Casting", path: manage_casting_path, icon: "casting",
        active: %w[casting casting_availability roles talent_pools casting_tables org_roles org_talent_pools org_availability].include?(controller_name) },
      { label: "Sign-ups", path: manage_signups_path, icon: "signups",
        active: %w[signups org_signups sign_up_forms auditions audition_cycles audition_requests audition_sessions sign_up_form_wizard audition_cycle_wizard org_auditions org_forms].include?(controller_name) },
      { label: "Courses", path: manage_course_offerings_path, icon: "courses",
        active: %w[course_offerings course_offering_wizard].include?(controller_name) },
      { label: "Documents", path: manage_org_documents_path, icon: "documents",
        active: %w[org_documents documents].include?(controller_name) },
      { label: "Contacts", path: manage_contacts_path, icon: "contacts",
        active: %w[directory people groups questionnaires].include?(controller_name) }
    ]

    # The Pro-tier modules, grouped under a small "Pro" heading so the whole set
    # reads as Pro without a badge on each one.
    pro_items = []
    # Staffing is limited to org owners/managers; it leads the Pro group.
    if Current.user&.superadmin? || Current.organization&.manageable_by?(Current.user)
      pro_items << { label: "Staffing", path: manage_staffing_index_path, icon: "staffing", locked: !on_paid_plan, feature: :staffing,
                     active: controller_path.to_s.start_with?("manage/staffing") }
    end
    pro_items += [
      { label: "Money", path: manage_money_index_path, icon: "money", locked: !on_paid_plan, feature: :money,
        active: %w[money money_financials money_payouts show_payouts show_financials money_settings].include?(controller_name) },
      # Contracts is its own Pro module — a deal with someone doesn't require Money.
      { label: "Contracts", path: manage_contracts_path, icon: "documents", locked: !on_paid_plan, feature: :contracts,
        active: %w[contracts contract_wizard contract_payments contract_documents contractors contract_settings].include?(controller_name) },
      { label: "Reports", path: manage_reports_path, icon: "reports", locked: !on_paid_plan, feature: :reports,
        active: controller_name == "reports" }
    ]

    [
      { label: nil, items: free_items },
      { label: "Pro", items: pro_items }
    ]
  end

  # --- Talent --------------------------------------------------------------
  # Mirrors shared/navigation/_my exactly.
  def talent_nav_sections
    items = [
      { label: "Home", path: my_dashboard_path, icon: "home", active: controller_name == "dashboard" },
      { label: "My Messages", path: my_messages_path, icon: "messages", active: controller_name == "messages",
        badge: Current.user&.unread_message_count.to_i },
      { label: "My Tasks & Availability", path: my_tasks_path, icon: "requests", active: controller_name == "tasks",
        badge: Current.user&.open_tasks_count.to_i },
      { label: "My Shows & Events", path: my_shows_path, icon: "shows", active: controller_name == "shows" }
    ]
    items << { label: "My Shifts", path: my_shifts_path, icon: "shifts", active: controller_name == "shifts" } if Current.user&.shows_my_shifts?
    items += [
      { label: "My Courses", path: my_courses_path, icon: "courses", active: controller_name == "courses" },
      { label: "My Auditions", path: my_auditions_path, icon: "auditions", active: controller_name == "auditions" },
      { label: "My Documents", path: my_documents_path, icon: "documents", active: controller_name == "documents" }
    ]
    items << { label: "My Contracts", path: my_contracts_path, icon: "documents", active: controller_name == "contracts" } if Current.user&.has_contracts?
    items += [
      { label: "My Payments", path: my_payments_path, icon: "payments", active: controller_name == "payments" },
      { label: "My Productions", path: my_productions_path, icon: "productions", active: controller_name == "productions" }
    ]
    [ { label: nil, items: items } ]
  end

  # --- Account -------------------------------------------------------------
  # Mirrors shared/navigation/_account exactly.
  def account_nav_sections
    [ { label: nil, items: [
      { label: "Account", path: account_path, icon: "account", active: action_name == "show" },
      { label: "Profiles", path: account_profiles_path, icon: "profiles", active: action_name == "profiles" },
      { label: "Organizations", path: account_organizations_path, icon: "organizations", active: action_name == "organizations" },
      { label: "Notifications", path: account_notifications_path, icon: "notifications", active: action_name == "notifications" }
    ] } ]
  end

  # --- Superadmin ----------------------------------------------------------
  # Mirrors shared/navigation/_superadmin exactly.
  def superadmin_nav_sections
    [
      { label: nil, items: [
        { label: "Overview", path: superadmin_path, icon: "overview", active: controller_name == "superadmin" && action_name == "index" },
        { label: "People", path: people_list_path, icon: "people", active: %w[people_list person_detail].include?(action_name) },
        { label: "Organizations", path: organizations_list_path, icon: "organizations", active: %w[organizations_list organization_detail organization_consolidation production_transfer].include?(action_name) },
        { label: "Open Mics", path: mics_index_path, icon: "mics", active: controller_name == "mics" }
      ] },
      { label: "Business", items: [
        { label: "Finances", path: finances_path, icon: "money", active: action_name.to_s.start_with?("finances") },
        { label: "Promo Codes", path: promo_codes_path, icon: "promo", active: action_name.to_s.start_with?("promo_code") },
        { label: "Demo Users", path: demo_users_path, icon: "people", active: action_name == "demo_users" }
      ] },
      { label: "Content", items: [
        { label: "Profiles", path: profiles_monitor_path, icon: "profiles", active: action_name == "profiles" },
        { label: "Email Logs", path: email_logs_path, icon: "messages", active: %w[email_logs email_log].include?(action_name) },
        { label: "Messages", path: messages_list_path, icon: "messages", active: %w[messages_list message_detail].include?(action_name) },
        { label: "Content Templates", path: content_templates_path, icon: "documents", active: action_name.to_s.start_with?("content_template") },
        { label: "Agreements", path: agreements_monitor_path, icon: "agreements", active: action_name == "agreements" },
        { label: "Keys", path: keys_monitor_path, icon: "keys", active: action_name == "keys" }
      ] },
      { label: "Technical", items: [
        { label: "Data", path: data_monitor_path, icon: "data", active: action_name == "data" },
        { label: "Cache", path: cache_monitor_path, icon: "bolt", active: action_name == "cache" },
        { label: "Storage", path: storage_monitor_path, icon: "storage", active: action_name == "storage" },
        { label: "Queue", path: queue_monitor_path, icon: "queue", active: action_name.to_s.start_with?("queue") }
      ] }
    ]
  end

  # Heroicon (outline) path data, keyed by nav icon name.
  NAV_ICON_PATHS = {
    "dot" => "M12 12h.01",
    "home" => "m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25",
    "messages" => "M21.75 6.75v10.5a2.25 2.25 0 0 1-2.25 2.25h-15a2.25 2.25 0 0 1-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25m19.5 0v.243a2.25 2.25 0 0 1-1.07 1.916l-7.5 4.615a2.25 2.25 0 0 1-2.36 0L3.32 8.91a2.25 2.25 0 0 1-1.07-1.916V6.75",
    "requests" => "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "shows" => "M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5",
    "shifts" => "M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "courses" => "M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25",
    "auditions" => "m15.75 10.5 4.72-4.72a.75.75 0 0 1 1.28.53v11.38a.75.75 0 0 1-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 0 0 2.25-2.25v-9a2.25 2.25 0 0 0-2.25-2.25h-9A2.25 2.25 0 0 0 2.25 7.5v9a2.25 2.25 0 0 0 2.25 2.25Z",
    "documents" => "M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z",
    "payments" => "M12 6v12m-3-2.818.879.659c1.171.879 3.07.879 4.242 0 1.172-.879 1.172-2.303 0-3.182C13.536 12.219 12.768 12 12 12c-.725 0-1.45-.22-2.003-.659-1.106-.879-1.106-2.303 0-3.182s2.9-.879 4.006 0l.415.33M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "productions" => "M2.25 21h19.5m-18-18v18m10.5-18v18m6-13.5V21M6.75 6.75h.75m-.75 3h.75m-.75 3h.75m3-6h.75m-.75 3h.75m-.75 3h.75M6.75 21v-3.375c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21M3 3h12m-.75 4.5H21m-3.75 3.75h.008v.008h-.008v-.008Zm0 3h.008v.008h-.008v-.008Zm0 3h.008v.008h-.008v-.008Z",
    "casting" => "M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z",
    "signups" => "M16.862 4.487l1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10",
    "contacts" => "M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z",
    "staffing" => "M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z",
    "money" => "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "reports" => "M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z",
    "account" => "M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.24-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z",
    "profiles" => "M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z",
    "organizations" => "M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21",
    "notifications" => "M14.857 17.082a23.848 23.848 0 0 0 5.454-1.31A8.967 8.967 0 0 1 18 9.75V9A6 6 0 0 0 6 9v.75a8.967 8.967 0 0 1-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 0 1-5.714 0m5.714 0a3 3 0 1 1-5.714 0",
    "overview" => "M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25Z",
    "people" => "M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z",
    "mics" => "M12 18.75a6 6 0 0 0 6-6v-1.5m-6 7.5a6 6 0 0 1-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 0 1-3-3V4.5a3 3 0 1 1 6 0v8.25a3 3 0 0 1-3 3Z",
    "promo" => "M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 0 0 2.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 0 0-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25ZM6.75 12h.008v.008H6.75V12Zm0 3h.008v.008H6.75V15Zm0 3h.008v.008H6.75V18Z",
    "agreements" => "M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 0 0 2.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 0 0-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25Z",
    "keys" => "M15.75 5.25a3 3 0 0 1 3 3m3 0a6 6 0 0 1-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1 1 21.75 8.25Z",
    "data" => "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125",
    "bolt" => "m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z",
    "storage" => "m20.25 7.5-.625 10.632a2.25 2.25 0 0 1-2.247 2.118H6.622a2.25 2.25 0 0 1-2.247-2.118L3.75 7.5M10 11.25h4M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125Z",
    "queue" => "M6 6.878V6a2.25 2.25 0 0 1 2.25-2.25h7.5A2.25 2.25 0 0 1 18 6v.878m-12 0c.235-.083.487-.128.75-.128h10.5c.263 0 .515.045.75.128m-12 0A2.25 2.25 0 0 0 4.5 9v.878m13.5-3A2.25 2.25 0 0 1 19.5 9v.878m0 0a2.246 2.246 0 0 0-.75-.128H5.25c-.263 0-.515.045-.75.128m15 0A2.25 2.25 0 0 1 21 12v6a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 18v-6c0-.98.626-1.813 1.5-2.122"
  }.freeze
end
