# frozen_string_literal: true

# The person's Notifications (V1.1 plan §9): everything automated that reached
# them, read or not, newest first. Universal, like Messages: the bell opens it
# from either mode, and it draws the panel of the mode they were last in.
class NotificationsController < ApplicationController
  include OrganizationContext

  skip_before_action :show_my_sidebar
  before_action :show_mode_sidebar, only: %i[index show]

  def index
    @filter = params[:filter] == "unread" ? "unread" : "all"
    @area = NotificationGroups.areas.include?(params[:area]) ? params[:area] : nil
    scope = Current.user.notifications.newest_first.includes(:organization)
    scope = scope.unread if @filter == "unread"
    scope = scope.in_category(NotificationGroups::ALL.select { |g| g.area == @area }.map(&:key)) if @area
    @pagy, @notifications = pagy(scope, limit: 40)
    @ask_before_switching = !in_production_mode? && Current.user.notification_preferences["switch_without_asking"] != true
  end

  # A tap from the list or a push: it's read now, then its page. A page in
  # production mode opens in that notification's organization.
  def open
    notification = Current.user.notifications.find(params[:id])
    notification.mark_read!
    if notification.production_mode? && notification.organization && Current.user.accessible_organizations.exists?(id: notification.organization_id)
      session[:current_organization_id] = {} unless session[:current_organization_id].is_a?(Hash)
      session[:current_organization_id][Current.user.id.to_s] = notification.organization_id
    end
    redirect_to notification.path.presence || (notification.body.present? ? notification_path(notification) : notifications_path)
  end

  # A notice with nothing to link to (it came with its words, from a
  # template that used to be a message): those words, on its own page.
  def show
    @notification = Current.user.notifications.find(params[:id])
    @notification.mark_read!
  end

  def mark_all_read
    Current.user.notifications.unread.update_all(read_at: Time.current)
    redirect_to notifications_path(filter: params[:filter], area: params[:area])
  end

  # "Don't ask again" on the prompt before a notification switches modes.
  def switch_without_asking
    Current.user.update!(notification_preferences: Current.user.notification_preferences.merge("switch_without_asking" => true))
    head :no_content
  end

  private

  def show_mode_sidebar
    if in_production_mode?
      set_current_organization
      set_current_production
      @show_manage_sidebar = true if Current.organization
    end
    @show_my_sidebar = true unless @show_manage_sidebar
  end
end
