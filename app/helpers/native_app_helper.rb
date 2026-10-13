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

  # Whether this copy of the app can do something native: Hotwire Native lists
  # the app's bridge components in its user agent ("bridge-components: [form
  # menu tap-to-pay]"). Tap to Pay is only in builds Apple lets take payments.
  def native_bridge_component?(name)
    turbo_native_app? && request.user_agent.to_s[/bridge-components: \[([^\]]*)\]/, 1].to_s.split.include?(name)
  end

  # Everything in My, as the menu's tiles: the web nav's items, each titled
  # "My …" like the page it opens (Tim, 2026-10-12), with SF Symbols, then
  # profile, groups (only for someone in one) and settings. badge is a count.
  # The Door isn't a tile: it comes last, as the menu's full-width bar, only
  # while a show someone can work is on (DoorTonight; Tim, 2026-10-13).
  # Signed out: an empty menu (the app shows just the sign-in screen).
  def native_menu
    user = native_user
    return [] unless user

    items = talent_nav_sections.flat_map { |section| section[:items] }.map { |item| native_menu_item(item) }
    items.reject! { |item| item[:id] == "door" }
    paths = [ profile_path, (groups_path if native_in_a_group?(user)), account_path ].compact
    items + paths.map { |path| native_menu_item(path: path) } + [ native_door_item(user) ].compact
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
      my_dashboard_path => [ "home", "My Calendar", "house" ],
      my_messages_path => [ "messages", "My Messages", "envelope" ],
      my_tasks_path => [ "tasks", "My Tasks", "checklist" ],
      my_shows_path => [ "shows", "My Shows", "calendar" ],
      my_shifts_path => [ "shifts", "My Shifts", "clock" ],
      door_index_path => %w[door Door qrcode.viewfinder],
      my_ticket_sales_path => [ "ticket_sales", "Ticket Sales", "chart.bar" ],
      my_courses_path => [ "courses", "My Courses", "book" ],
      my_auditions_path => [ "auditions", "My Auditions", "theatermasks" ],
      my_documents_path => [ "documents", "My Documents", "doc.text" ],
      my_contracts_path => [ "contracts", "My Contracts", "signature" ],
      my_payments_path => [ "payments", "My Payments", "dollarsign.circle" ],
      my_productions_path => [ "productions", "My Productions", "building.2" ],
      profile_path => %w[profile Profile person.crop.circle],
      groups_path => %w[groups Groups person.3],
      account_path => %w[settings Settings gearshape]
    }.fetch(path) { [ path.parameterize, item[:label], "circle" ] }
    { id: id, title: title, path: path, icon: icon, badge: item[:badge].to_i }
  end

  # The Door, while a show is on: straight to that show's door when there's
  # one, otherwise the list of tonight's. subtitle says which and when. An
  # organization set to keep it all the time (Ticketing settings → Door) gets
  # the list, naming the next show, when nothing's on.
  def native_door_item(user)
    listings = DoorTonight.listings_for(user)
    if listings.empty?
      return nil unless DoorTonight.always?(user)

      upcoming = DoorTonight.next_listing(user)
      subtitle = upcoming ? "Next: #{upcoming.display_title} · #{upcoming.show.date_and_time.strftime('%a, %b %-d')}" : "No shows coming up"
      { id: "door", title: "Work the door", path: door_index_path, icon: "qrcode.viewfinder", badge: 0, subtitle: subtitle }
    elsif listings.one?
      listing = listings.first
      starts = listing.show.date_and_time
      verb = starts <= Time.current ? "Started" : "Starts"
      { id: "door", title: "Work the door", path: door_path(listing), icon: "qrcode.viewfinder", badge: 0,
        subtitle: "#{listing.display_title} · #{verb} #{starts.strftime('%-l:%M %p')}" }
    else
      { id: "door", title: "Work the door", path: door_index_path, icon: "qrcode.viewfinder", badge: 0,
        subtitle: "#{listings.size} shows on now" }
    end
  end

  # Groups are a niche corner; the menu only offers them to someone in one.
  def native_in_a_group?(user)
    return @native_in_a_group if defined?(@native_in_a_group)

    @native_in_a_group = GroupMembership.joins(:group).where(person_id: user.people.active.select(:id), groups: { archived_at: nil }).exists?
  end
end
