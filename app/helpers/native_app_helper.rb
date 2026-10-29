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

  # The app build's navigation generation (NativeAppVersion): 1 for V1
  # installs, 2 for V1.1. Nil outside the app.
  def native_nav_generation
    NativeAppVersion.nav(request.user_agent)
  end

  # Whether this page may show production mode and the V1.1 navigation: the
  # whole website, and app builds that draw it. V1 installs never do.
  def production_mode_available?
    NativeAppVersion.production_mode?(request.user_agent)
  end

  # The store this phone's web browser belongs to (:ios or :android), or nil
  # on a desktop and inside the app itself. For "get the app" nudges that
  # name one store, never two.
  def phone_store
    AppStores.platform(request.user_agent)
  end

  # The Android app (Hotwire Native Android's user agent says so); the
  # iPhone app otherwise.
  def native_android?
    turbo_native_app? && request.user_agent.to_s.include?("Android")
  end

  # The phone's own Settings, in words: where notifications are turned off.
  def native_settings_name
    native_android? ? "your phone's Settings" : "iPhone Settings"
  end

  # Tap to Pay's name. On iPhone it's always Apple's whole "Tap to Pay on
  # iPhone" (Apple's review); the Android app's is plain "Tap to Pay", and
  # never names Apple or its phone.
  def tap_to_pay_name
    native_android? ? "Tap to Pay" : "Tap to Pay on iPhone"
  end

  # The door phone, in Tap to Pay's words: "this iPhone" or "this phone".
  def tap_to_pay_phone
    native_android? ? "phone" : "iPhone"
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

    items = talent_nav_sections.flat_map { |section| section[:items] }.reject { |item| item[:web_only] }.map { |item| native_menu_item(item) }
    items.reject! { |item| item[:id] == "door" }
    paths = [ profile_path, (groups_path if native_in_a_group?(user)), account_path ].compact
    # Only the My pages (Tim's rule): no Tap to Pay, ticketing or door tile.
    # The door is the Work the door bar under the menu.
    items + paths.map { |path| native_menu_item(path: path) } + [ native_door_item(user) ].compact
  end

  # Tap to Pay, for an app that has it, when this person can sell
  # at a door that has it switched on (TapToPay.organizations_for): where its
  # page is, what the app warms Terminal up with at launch (Apple 1.5), and
  # whether they may accept Apple's terms (3.8). Nil otherwise, and the app
  # shows nothing of Tap to Pay.
  def native_tap_to_pay
    return @native_tap_to_pay if defined?(@native_tap_to_pay)

    user = native_user
    @native_tap_to_pay = if user && native_bridge_component?("tap-to-pay")
      organization = TapToPay.organizations_for(user).first
      if organization
        { settingsPath: door_tap_to_pay_path, userKey: user.id.to_s, canAcceptTerms: TapToPay.can_accept_terms?(user),
          locationId: organization.stripe_terminal_location_id,
          connectionTokenUrl: door_tap_to_pay_token_url(organization_id: organization.id) }
      end
    end
  end

  # The V1.1 menu, for generation-2 builds only (NativeAppVersion); nil for
  # V1 installs, which keep reading native_menu unchanged. One list the app
  # draws natively (navigation canvas, app row):
  #   mode          "my" or "production"
  #   sections      [{ label:, items: [{ id, title, path, icon, badge, locked }] }]
  #                 (the panel's nav: no Messages tile)
  #   icons         Messages and Notifications for the nav bar, with counts
  #   organization  in production mode: name, initials, and where its sheet opens
  #   door          the Work the door bar (black), or nil
  #   modeSwitch    Enter or Exit production mode (CocoScout pink), or nil
  #   profilePath, settingsPath, signOutPath for the person card
  # The floating Coco button carries no badge (Tim, 2026-10-20).
  def native_nav
    user = native_user
    return nil unless user && native_nav_generation.to_i >= 2

    production = native_production_mode?
    context = production ? :production : :talent
    icons = panel_universal_icons(production_mode: production)
    {
      mode: production ? "production" : "my",
      sections: panel_nav_sections(context).map do |section|
        { label: section[:label], items: section[:items].reject { |item| item[:web_only] }.map { |item| native_nav_item(item) } }
      end,
      icons: {
        messages: { path: icons[:messages][:path], count: icons[:messages][:count] },
        notifications: { path: icons[:notifications][:path], count: icons[:notifications][:count] }
      },
      organization: (if production
                       { name: Current.organization.name, initials: Current.organization.initials, sheetPath: select_organization_path }
                     end),
      door: (production ? nil : native_door_item(user)),
      modeSwitch: panel_mode_switch(production_mode: production)&.slice(:label, :subtitle, :path, :enter),
      profilePath: profile_path, settingsPath: account_path, signOutPath: "/signout"
    }
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
    items = talent_nav_sections.flat_map { |section| section[:items] }.reject { |item| item[:path] == my_dashboard_path || item[:web_only] }
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

  # In production mode: a Manage page with its organization chosen, or a
  # page that belongs to both modes or neither, opened from production mode:
  # Messages and Notifications draw its frame (@show_manage_sidebar); Account
  # settings, Profile and Groups keep it (ModeNeutralPage). Opening one is
  # not leaving production mode (Tim, 2026-10-29).
  def native_production_mode?
    (controller_path.to_s.start_with?("manage") || @show_manage_sidebar || @keep_production_mode) && Current.organization.present?
  end

  # A tile for the V1.1 menu: My's tiles keep their names and symbols
  # (native_menu_item); production mode's are the nav's own names.
  NATIVE_NAV_SYMBOLS = {
    "home" => "house", "shows" => "calendar", "casting" => "theatermasks", "signups" => "list.bullet.clipboard",
    "courses" => "book", "documents" => "doc.text", "contacts" => "person.2", "productions" => "building.2",
    "ticketing" => "ticket", "mailing_lists" => "envelope.open", "staffing" => "clock", "money" => "dollarsign.circle", "reports" => "chart.bar"
  }.freeze

  def native_nav_item(item)
    if item[:path].to_s.start_with?("/manage")
      { id: "manage-#{item[:icon]}-#{item[:label].parameterize}", title: item[:label], path: item[:path],
        icon: NATIVE_NAV_SYMBOLS.fetch(item[:icon].to_s, "circle"), badge: item[:badge].to_i, locked: item[:locked] ? true : false }
    else
      # V1.1's words (Tim, 2026-10-21): "Home" and "My Shows & Events" on My;
      # V1 keeps its own (native_menu_item).
      tile = native_menu_item(item)
      tile = tile.merge(title: { "home" => "Home", "shows" => "My Shows & Events" }.fetch(tile[:id], tile[:title]))
      tile.merge(locked: false)
    end
  end

  # The Door, while a show is on: the same bar the website draws under the
  # menu (NavigationHelper#door_bar_item).
  def native_door_item(user)
    door_bar_item(user)
  end

  # Groups are a niche corner; the menu only offers them to someone in one.
  def native_in_a_group?(user)
    return @native_in_a_group if defined?(@native_in_a_group)

    @native_in_a_group = GroupMembership.joins(:group).where(person_id: user.people.active.select(:id), groups: { archived_at: nil }).exists?
  end
end
