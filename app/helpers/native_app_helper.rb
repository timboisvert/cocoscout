# frozen_string_literal: true

# What the iOS (and later Android) app shows natively for the signed-in person:
# its full-screen menu (with badges) and who's signed in, for the menu's pink
# card. Built from the same rules as the web nav
# (NavigationHelper#talent_nav_sections), so the app and the website never
# disagree about who sees what.
module NativeAppHelper
  # The viewport for every page the app shows. App pages never zoom: iPhone
  # zooms in on any text box under 16px when it's tapped, and since the app
  # keeps one web view, the zoom stuck to every page after. Browsers keep
  # pinch-zoom. cover: the door's own header handles the notch in a browser.
  def native_viewport(cover: false)
    if turbo_native_app?
      "width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=1"
    else
      "width=device-width,initial-scale=1,minimum-scale=1,maximum-scale=5#{',viewport-fit=cover' if cover}"
    end
  end

  # Everything in My, as the menu's tiles: the web nav's items with short
  # titles and SF Symbols, the Door for anyone who can work one, then
  # profile, groups (only for someone in one) and settings. badge is a count.
  # Signed out: an empty menu (the app shows just the sign-in screen).
  def native_menu
    user = native_user
    return [] unless user

    items = talent_nav_sections.flat_map { |section| section[:items] }.map { |item| native_menu_item(item) }
    if native_works_door?(user) && items.none? { |item| item[:id] == "door" }
      items.insert(items.index { |item| item[:id] == "shows" }.to_i + 1, native_menu_item(path: door_index_path))
    end
    paths = [ profile_path, (groups_path if native_in_a_group?(user)), account_path ].compact
    items + paths.map { |path| native_menu_item(path: path) }
  end

  # Who's signed in, for the top of the menu. headshot_path is relative to
  # the site (the app adds its own host).
  def native_person
    user = native_user
    return nil unless user

    person = user.person
    variant = person&.safe_headshot_variant(:thumb)
    {
      name: person&.name.presence || user.email_address,
      email: user.email_address,
      initials: person&.initials.presence || user.email_address[0].upcase,
      headshot_path: variant && url_for(variant)
    }
  end

  # /my/account's list: everything in My but Home, then the profile and
  # account pages.
  def native_more_items
    items = talent_nav_sections.flat_map { |section| section[:items] }.reject { |item| item[:path] == my_dashboard_path }
    items + [
      { label: "My Profile", path: profile_path, icon: "profiles" },
      ({ label: "My Groups", path: groups_path, icon: "people" } if native_in_a_group?(Current.user)),
      { label: "Account Settings", path: account_path, icon: "account" }
    ].compact
  end

  private

  # The signed-in person, even on pages open to everyone (the password and
  # sign-in pages skip loading the session, and an empty answer here would
  # tell the app you'd signed out).
  def native_user
    authenticated? if respond_to?(:authenticated?)
    Current.user
  end

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

  # Groups are a niche corner; the menu only offers them to someone in one.
  def native_in_a_group?(user)
    return @native_in_a_group if defined?(@native_in_a_group)

    @native_in_a_group = GroupMembership.joins(:group).where(person_id: user.people.active.select(:id), groups: { archived_at: nil }).exists?
  end

  # Anyone who can work a door: a granted volunteer, or the theater's managers
  # (who'd use Ticketing on the web, but have no /manage in the app).
  def native_works_door?(user)
    TicketingDoorAccess.organizations_for(user).any?
  end
end
