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

  # The More screen: everything in the web nav that isn't a tab, then the
  # profile and account pages.
  def native_more_items
    tab_paths = native_tabs.map { |tab| tab[:path] }
    items = talent_nav_sections.flat_map { |section| section[:items] }.reject { |item| tab_paths.include?(item[:path]) }
    items + [
      { label: "My Profile", path: profile_path, icon: "profiles" },
      { label: "My Groups", path: groups_path, icon: "people" },
      { label: "Account Settings", path: account_path, icon: "account" }
    ]
  end

  private

  # House staff who aren't performers get Shifts where performers get Tasks.
  def native_staff_only?(user)
    user.shows_my_shifts? && !TalentPoolMembership.where(member_type: "Person", member_id: user.people.active.select(:id)).exists?
  end

  # Anyone who can work a door: a granted volunteer, or the theater's managers
  # (who'd use Ticketing on the web, but have no /manage in the app).
  def native_door_tab?(user)
    TicketingDoorAccess.organizations_for(user).any?
  end
end
