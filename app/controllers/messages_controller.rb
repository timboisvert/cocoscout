# frozen_string_literal: true

# The one Messages page (V1.1; Tim, 2026-10-21: "one single messages page
# that changes based on the context"): every thread the person is in, at
# one address, drawn in the frame of the mode they're in (like
# Notifications). The list and filters are MessagesInbox; production mode
# adds Send a message (compose) and the intro guide; My adds Message a
# production (a sheet of the productions they can write to, then the
# contact window), and the Notifications row for V1 apps with no bell.
class MessagesController < ApplicationController
  include MessagesInbox
  include OrganizationContext
  include ContactableProductions

  skip_before_action :show_my_sidebar
  before_action :show_mode_sidebar
  before_action :track_inbox_visit, only: :index

  def index
    load_inbox
    if @production_mode
      @accessible_productions = Current.user.accessible_productions
        .where(organization: Current.organization)
        .includes(:talent_pools, talent_pool_shares: :talent_pool)
        .order(:name)
    else
      @contactable_productions = productions_user_can_contact.to_a
      @contact_reasons = contact_reasons(@contactable_productions)
    end
  end

  # One inbox, one count: everything unread is read now.
  def mark_all_read
    Current.user.message_subscriptions.active.each(&:mark_read!)
    redirect_to messages_path, notice: "All messages marked as read"
  end

  private

  def show_mode_sidebar
    if in_production_mode?
      set_current_organization
      set_current_production
      @show_manage_sidebar = true if Current.organization
    end
    @production_mode = @show_manage_sidebar ? true : false
    @show_my_sidebar = true unless @show_manage_sidebar
  end

  def track_inbox_visit
    Current.user.touch(:last_inbox_visit_at)
  end
end
