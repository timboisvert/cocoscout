# frozen_string_literal: true

# Which organization and production someone is working in, from the session,
# and which mode they're in. Manage uses it on every page; the universal pages
# (Notifications, which belong to neither mode) use it to draw the panel of
# the mode the person was last in. Was ManageController's own until V1.1.
module OrganizationContext
  extend ActiveSupport::Concern

  private

  # "manage" or "my": the mode this person was last in on this browser, or
  # on their account when this browser hasn't seen them pick one.
  def last_mode
    return "my" unless Current.user

    prefs = cookies.encrypted[:last_dashboard]
    remembered = prefs.is_a?(Hash) ? prefs[Current.user.id.to_s] : nil
    (remembered || Current.user.last_mode) == "manage" ? "manage" : "my"
  end

  def in_production_mode?
    last_mode == "manage" && NativeAppVersion.production_mode?(request.user_agent)
  end

  # An opener (a message, a notification) sending someone into an
  # organization's production mode: the session's organization, and a word
  # for the next page when that's a change of organization or of mode
  # (shared/navigation/mode_switch_notice reads flash[:switched_to]).
  def switch_organization!(organization_id)
    user_id = Current.user.id.to_s
    session[:current_organization_id] = {} unless session[:current_organization_id].is_a?(Hash)
    was = session[:current_organization_id][user_id]
    session[:current_organization_id][user_id] = organization_id
    return if was == organization_id && last_mode == "manage"

    flash[:switched_to] = Organization.find_by(id: organization_id)&.name
  end

  # The session holds the organization someone is working in, but the session
  # ends when the browser quits or the app is closed, while they stay signed
  # in. Someone with several organizations was then asked to pick one again
  # every time they came back (Tim, 2026-11-09). So this browser, or this
  # phone's app, also keeps the last one for a year, and the session starts
  # from it. Per person, as last_dashboard is.
  def set_current_organization
    user_id = Current.user&.id
    if user_id && session[:current_organization_id].is_a?(Hash)
      company_id = session[:current_organization_id][user_id.to_s] || remembered_organization_id
      org = Organization.find_by(id: company_id)
      # Verify user still has access to this org (role may have been removed)
      if org && Current.user.accessible_organizations.where(id: org.id).exists?
        session[:current_organization_id][user_id.to_s] = org.id
        Current.organization = org
        use_time_zone_of(org)
      else
        session[:current_organization_id].delete(user_id.to_s)
        Current.organization = nil
      end
    elsif Current.user
      orgs = Current.user.accessible_organizations
      # Where they were last time on this browser, while they still belong
      # to it; otherwise the one organization someone has is picked for them.
      auto_select_org = orgs.find_by(id: remembered_organization_id) if remembered_organization_id
      auto_select_org ||= orgs.first if orgs.one?

      if auto_select_org
        session[:current_organization_id] ||= {}
        session[:current_organization_id][Current.user.id.to_s] = auto_select_org.id
        Current.organization = auto_select_org
        use_time_zone_of(auto_select_org)
      else
        Current.organization = nil
      end
    else
      Current.organization = nil
    end
    remember_organization
  end

  # The organization this person last worked in on this browser, or nil.
  def remembered_organization_id
    return nil unless Current.user

    kept = cookies.encrypted[:last_organization]
    kept.is_a?(Hash) ? kept[Current.user.id.to_s] : nil
  end

  # Written only when it changes, so most pages set no cookie.
  def remember_organization
    return unless Current.user && Current.organization
    return if remembered_organization_id == Current.organization.id

    kept = cookies.encrypted[:last_organization]
    kept = {} unless kept.is_a?(Hash)
    kept[Current.user.id.to_s] = Current.organization.id
    cookies.encrypted[:last_organization] = { value: kept, expires: 1.year.from_now, httponly: true }
  end

  def set_current_production
    user_id = Current.user&.id
    if user_id && Current.organization && session[:current_production_id_for_organization].is_a?(Hash)
      prod_id = session[:current_production_id_for_organization]["#{user_id}_#{Current.organization.id}"]
      production = if prod_id
                     Current.organization.productions.includes(posters: { image_attachment: :blob }).find_by(id: prod_id)
      end
      # Only honor the stored selection if the user can actually open it. This
      # prevents a stale/archived/foreign selection (e.g. left over from
      # impersonation or a shared browser) from leaking onto org-level pages
      # like Messages and tripping the production access guard.
      Current.production = (production && Current.user.can_access_production?(production)) ? production : nil
    else
      Current.production = nil
    end
  end
end
