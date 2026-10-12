# frozen_string_literal: true

# What the iOS (and later Android) app shows natively for the signed-in person:
# the tab bar and its badges, and the More screen's list. Built from the same
# rules as the web nav (NavigationHelper#talent_nav_sections), so the app and
# the website never disagree about who sees what.
module NativeAppHelper
  # The tab bar, in order. icon is an SF Symbol name; badge is a count.
  # Signed out: no tabs (the app shows just the sign-in screen).
  def native_tabs
    user = Current.user
    return [] unless user

    tabs = [ { id: "home", title: "Home", path: my_dashboard_path, icon: "house" } ]
    tabs << if native_staff_only?(user)
      { id: "shifts", title: "Shifts", path: my_shifts_path, icon: "clock" }
    else
      { id: "tasks", title: "Tasks", path: my_tasks_path, icon: "checklist", badge: user.open_tasks_count.to_i }
    end
    tabs << { id: "messages", title: "Messages", path: my_messages_path, icon: "envelope", badge: user.unread_message_count.to_i }
    tabs << { id: "door", title: "Door", path: door_index_path, icon: "qrcode.viewfinder" } if native_door_tab?(user)
    tabs << { id: "more", title: "More", path: my_account_path, icon: "person.crop.circle" }
    tabs
  end

  # Everything in My, for the app's full-screen menu (the one-button and
  # mixed navigation styles): the web nav's items with short titles and
  # SF Symbols, the Door for anyone who can work one, then profile, groups
  # (only for someone in one) and settings.
  def native_menu
    user = Current.user
    return [] unless user

    items = talent_nav_sections.flat_map { |section| section[:items] }.map { |item| native_menu_item(item) }
    if native_door_tab?(user) && items.none? { |item| item[:id] == "door" }
      items.insert(items.index { |item| item[:id] == "shows" }.to_i + 1, native_menu_item(path: door_index_path))
    end
    paths = [ profile_path, (groups_path if native_in_a_group?(user)), account_path ].compact
    items + paths.map { |path| native_menu_item(path: path) }
  end

  # The More screen: everything in the web nav that isn't a tab, then the
  # profile and account pages.
  def native_more_items
    tab_paths = native_tabs.map { |tab| tab[:path] }
    items = talent_nav_sections.flat_map { |section| section[:items] }.reject { |item| tab_paths.include?(item[:path]) }
    items + [
      { label: "My Profile", path: profile_path, icon: "profiles" },
      ({ label: "My Groups", path: groups_path, icon: "people" } if native_in_a_group?(Current.user)),
      { label: "Account Settings", path: account_path, icon: "account" }
    ].compact
  end

  private

  # Short title, SF Symbol and id for one menu item, by where it goes.
  def native_menu_item(item)
    path = item[:path]
    id, title, icon = {
      my_dashboard_path => %w[home Home house],
      my_messages_path => %w[messages Messages envelope],
      my_tasks_path => %w[tasks Tasks checklist],
      my_shows_path => %w[shows Shows calendar],
      my_shifts_path => %w[shifts Shifts clock],
      door_index_path => %w[door Door qrcode.viewfinder],
      my_ticket_sales_path => [ "ticket_sales", "Ticket Sales", "chart.bar" ],
      my_courses_path => %w[courses Courses book],
      my_auditions_path => %w[auditions Auditions theatermasks],
      my_documents_path => %w[documents Documents doc.text],
      my_contracts_path => %w[contracts Contracts signature],
      my_payments_path => %w[payments Payments dollarsign.circle],
      my_productions_path => %w[productions Productions building.2],
      profile_path => %w[profile Profile person.crop.circle],
      groups_path => %w[groups Groups person.3],
      account_path => %w[settings Settings gearshape]
    }.fetch(path) { [ path.parameterize, item[:label], "circle" ] }
    { id: id, title: title, path: path, icon: icon, badge: item[:badge].to_i }
  end

  # House staff who aren't performers get Shifts where performers get Tasks.
  def native_staff_only?(user)
    user.shows_my_shifts? && !TalentPoolMembership.where(member_type: "Person", member_id: user.people.active.select(:id)).exists?
  end

  # Groups are a niche corner; the menu only offers them to someone in one.
  def native_in_a_group?(user)
    return @native_in_a_group if defined?(@native_in_a_group)

    @native_in_a_group = GroupMembership.joins(:group).where(person_id: user.people.active.select(:id), groups: { archived_at: nil }).exists?
  end

  # Anyone who can work a door: a granted volunteer, or the theater's managers
  # (who'd use Ticketing on the web, but have no /manage in the app).
  def native_door_tab?(user)
    TicketingDoorAccess.organizations_for(user).any?
  end
end
