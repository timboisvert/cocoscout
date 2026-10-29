# frozen_string_literal: true

module Manage
  # Mailing lists (Pro, V1.1; Tim 2026-10-23): the module's home (lists,
  # segments, emails) and one list's page (its followers, where it collects,
  # and its actions). Lists aren't shared outside the organization (Tim,
  # 2026-10-28: My Followers is gone).
  class MailingListsController < ManageController
    before_action :set_list, only: %i[show update update_productions archive unarchive export]

    PER_PAGE = 50

    def index
      @main_list = MailingList.main_for!(Current.organization)
      @lists = Current.organization.mailing_lists.active.main_first.to_a
      @archived_lists = Current.organization.mailing_lists.where.not(archived_at: nil).order(:name).to_a
      @counts = MailingListMembership.joins(:follower).where(mailing_list_id: @lists.map(&:id), followers: { status: "subscribed" })
                                     .group(:mailing_list_id).count
      @collects = MailingListProduction.where(mailing_list_id: @lists.map(&:id)).group(:mailing_list_id).count
      @follower_total = Current.organization.followers.subscribed.count
      @segments = Current.organization.segments.order(:name).to_a
      @drafts = Current.organization.follower_emails.drafts.limit(10).to_a
      @sent = Current.organization.follower_emails.sent_or_sending.limit(20).to_a
      @sales = sales_by_email(@sent)
      @allowance = FollowerEmailAllowance.new(Current.organization)
    end

    def show
      @filter = params[:filter].presence_in(%w[subscribed unsubscribed bounced]) || "subscribed"
      @source = params[:source].presence_in(FollowerSource::KINDS)
      @q = params[:q].to_s.strip
      scope = @list.followers.includes(:person, follower_sources: %i[production added_by_person])
      scope = case @filter
      when "unsubscribed" then scope.where(status: "unsubscribed")
      when "bounced" then scope.where(status: %w[bounced complained])
      else scope.where(status: "subscribed")
      end
      scope = scope.where(id: FollowerSource.where(kind: @source).select(:follower_id)) if @source
      scope = scope.where("followers.email ILIKE :q OR followers.name ILIKE :q", q: "%#{Follower.sanitize_sql_like(@q)}%") if @q.present?
      @order = params[:order] == "oldest" ? "oldest" : "newest"
      scope = scope.order(mailing_list_memberships: { created_at: @order == "oldest" ? :asc : :desc })
      @page = [ params[:page].to_i, 1 ].max
      @total = scope.count
      @followers = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
      @status_counts = @list.followers.group(:status).count
      @productions = @list.productions.order(:name).to_a
      @all_productions = Current.organization.productions.active.where.not(production_type: "course").order(:name).to_a
    end

    def create
      list = Current.organization.mailing_lists.create(name: params.dig(:mailing_list, :name), kind: "group")
      if list.persisted?
        redirect_to manage_mailing_list_path(list), notice: "#{list.name} is ready. Add people, or pick productions for it to collect from."
      else
        redirect_to manage_mailing_lists_path, alert: "Give the list a name."
      end
    end

    def update
      attrs = params.require(:mailing_list).permit(:name, :checkout_words)
      attrs.delete(:name) if @list.main? # the main list keeps the organization's name
      if @list.update(attrs)
        redirect_to manage_mailing_list_path(@list), notice: "Saved."
      else
        redirect_to manage_mailing_list_path(@list), alert: @list.errors.full_messages.to_sentence
      end
    end

    # Which productions' checkout offers this list's box.
    def update_productions
      return redirect_to(manage_mailing_list_path(@list), alert: "Your main list is on every production's checkout.") if @list.main?

      ids = Current.organization.productions.where(id: Array(params[:production_ids])).pluck(:id)
      MailingList.transaction do
        @list.mailing_list_productions.where.not(production_id: ids).destroy_all
        (ids - @list.mailing_list_productions.pluck(:production_id)).each { |id| @list.mailing_list_productions.create!(production_id: id) }
      end
      redirect_to manage_mailing_list_path(@list), notice: ids.any? ? "Checkout for those productions now offers this list." : "This list doesn't collect at checkout now."
    end

    def archive
      return redirect_to(manage_mailing_list_path(@list), alert: "Your main list can't be archived.") if @list.main?

      @list.update!(archived_at: Time.current)
      redirect_to manage_mailing_lists_path, notice: "#{@list.name} is archived. It stopped collecting; its followers are kept."
    end

    def unarchive
      @list.update!(archived_at: nil)
      redirect_to manage_mailing_list_path(@list), notice: "#{@list.name} is back."
    end

    # A spreadsheet of the list, emailed to the manager (FollowersExportJob).
    def export
      person = Current.user.person
      return redirect_to(manage_mailing_list_path(@list), alert: "Your account needs a profile to get the spreadsheet.") unless person

      FollowersExportJob.perform_later(person.id, list_id: @list.id)
      redirect_to manage_mailing_list_path(@list), notice: "We're making the spreadsheet. It'll be in your email in a minute."
    end

    # From a person's page in Contacts: add them to a list.
    def add_person
      person = Current.organization.people.find(params[:person_id])
      list = Current.organization.mailing_lists.active.find(params[:mailing_list_id])
      follower = Follower.for!(Current.organization, person.email, name: person.name)
      if follower.subscribed? || follower.status == "unsubscribed"
        list.mailing_list_memberships.find_or_create_by!(follower: follower)
        follower.follower_sources.create!(kind: "contacts", mailing_list: list, occurred_at: Time.current,
                                          added_by_person: Current.user.person)
      end
      notice = follower.subscribed? ? "#{person.name} is on #{list.name}." : "#{person.name} unsubscribed from your emails, so they won't get them."
      redirect_back fallback_location: manage_mailing_list_path(list), notice: notice
    end

    private

    def set_list
      @list = Current.organization.mailing_lists.find(params[:id])
    end

    # Tickets and money each sent email brought in, by its campaign.
    def sales_by_email(emails)
      FollowerEmailSales.for(Current.organization, emails)
    end
  end
end
