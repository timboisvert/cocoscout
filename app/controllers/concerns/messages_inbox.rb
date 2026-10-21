# frozen_string_literal: true

# The one Messages inbox (V1.1 plan §0a; Tim, 2026-10-21): the same list and
# the same count behind the mail icon in both modes. Every thread the person
# is in, each row saying which hat it's under: nothing for a thread they're in
# as a performer, a pill naming the organization for a thread of a production
# they run. The "For" chips keep one hat or one organization; opening a row
# goes through My::MessagesController#open, which switches organization (and
# mode) when the thread lives somewhere else, after asking.
module MessagesInbox
  extend ActiveSupport::Concern

  FILTERS = %w[all unread sent_by_me archived].freeze

  included do
    helper_method :production_side_thread?
  end

  private

  def load_inbox
    user = Current.user
    @filter = params[:filter].presence_in(FILTERS) || "all"
    @search = params[:q].to_s.strip
    @production_filter = params[:production_id].presence
    @order = params[:order] == "oldest" ? "oldest" : "newest"
    @hat = params[:hat].to_s

    @managed_organizations = user.accessible_organizations.order(:name).to_a
    @managed_organization_ids = @managed_organizations.map(&:id).to_set
    @managed_production_ids = user.production_ids_everywhere.to_set

    @messages = Message.inbox_for(user, archived: @filter == "archived")
    case @filter
    when "unread" then @messages = @messages.where(id: user.message_subscriptions.unread.select(:message_id))
    when "sent_by_me" then @messages = @messages.where(sender: user)
    end
    @messages = @messages.where(production_id: @production_filter) if @production_filter

    if @hat == "performer"
      @messages = @messages.where.not(id: production_side(Message.all).select(:id))
    elsif (org_id = @hat[/\Aorg:(\d+)\z/, 1]) && @managed_organization_ids.include?(org_id.to_i)
      org_production_ids = @managed_production_ids & Production.where(organization_id: org_id).pluck(:id).to_set
      @messages = @messages.where(id: Message.where(production_id: org_production_ids.to_a).or(Message.where(production_id: nil, organization_id: org_id)).select(:id))
    else
      @hat = ""
    end

    if @search.present?
      @messages = @messages.left_joins(:rich_text_body)
                           .where("messages.subject ILIKE :q OR action_text_rich_texts.body ILIKE :q", q: "%#{@search}%")
    end

    @messages = @messages.includes(:sender, :message_recipients, :child_messages, :show, :organization, :message_poll, production: :organization, images_attachments: :blob)
                         .order(updated_at: @order == "oldest" ? :asc : :desc)
    @pagy, @messages = pagy(@messages, limit: 25)
    @thread_summaries = Message.thread_summaries_for(@messages, current_user: user)
    @unread_count = user.unread_message_count

    # The production dropdown: every production with a thread in the inbox.
    @inbox_productions = Production.where(id: Message.inbox_for(user).where.not(production_id: nil).distinct.select(:production_id)).order(:name).to_a
    @ask_before_switching = user.notification_preferences["switch_without_asking"] != true
  end

  # Threads under the production hat: a production this person can open, or a
  # private thread with no production in an organization they can open.
  def production_side(scope)
    scope.where(production_id: @managed_production_ids.to_a)
         .or(scope.where(production_id: nil, organization_id: @managed_organization_ids.to_a))
  end

  def production_side_thread?(thread)
    @managed_production_ids.include?(thread.production_id) ||
      (thread.production_id.nil? && @managed_organization_ids.include?(thread.organization_id))
  end
end
