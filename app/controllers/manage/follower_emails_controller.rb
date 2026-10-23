# frozen_string_literal: true

module Manage
  # Writing and sending an email to followers, and what a sent one did.
  # "Review and send" saves the draft, then the page opens the send window
  # (who gets it, the exact email) whose Send posts deliver.
  class FollowerEmailsController < ManageController
    include TicketingHelper

    before_action :set_email, except: :new

    # A new draft, aimed at a list or segment, or announcing a show.
    def new
      email = Current.organization.follower_emails.new(created_by: Current.user, status: "draft")
      list = Current.organization.mailing_lists.active.find_by(id: params[:list_id])
      segment = Current.organization.segments.find_by(id: params[:segment_id])
      main = MailingList.main_for!(Current.organization)
      email.targets = { "list_ids" => [ (list || (segment ? nil : main))&.id ].compact, "segment_ids" => [ segment&.id ].compact }
      if (show = announce_show)
        words = FollowerTemplates.render("follower_email_announce",
                                         first_name: "{{first_name}}", show_title: show.secondary_name.presence || show.production.name,
                                         show_date: show.date_and_time.strftime("%A, %B %-d"), show_time: show.date_and_time.strftime("%-l:%M %p"),
                                         organization_name: Current.organization.name)
        email.subject = CGI.unescapeHTML(words[:subject])
        email.body = words[:body]
        email.show_ids = [ show.id ]
      end
      email.save!
      redirect_to manage_edit_follower_email_path(email)
    end

    def edit
      return redirect_to(manage_follower_email_path(@email)) unless @email.draft?

      load_choices
      @review = params[:review].present?
      @audience = @email.audience if @review
      @allowance = FollowerEmailAllowance.new(Current.organization)
    end

    def update
      return redirect_to(manage_follower_email_path(@email)) unless @email.draft?

      attrs = params.require(:follower_email).permit(:subject, :preheader, :body)
      @email.assign_attributes(attrs)
      @email.targets = {
        "list_ids" => Current.organization.mailing_lists.active.where(id: Array(params[:list_ids])).pluck(:id),
        "segment_ids" => Current.organization.segments.where(id: Array(params[:segment_ids])).pluck(:id)
      }
      @email.show_ids = Show.joins(:production).where(productions: { organization_id: Current.organization.id }, id: Array(params[:show_ids])).pluck(:id)
      @email.save!
      if params[:review].present?
        redirect_to manage_edit_follower_email_path(@email, review: 1)
      else
        redirect_to manage_edit_follower_email_path(@email), notice: "Draft saved."
      end
    end

    def destroy
      return redirect_to(manage_follower_email_path(@email)) unless @email.draft?

      @email.destroy!
      redirect_to manage_mailing_lists_path, notice: "Draft deleted."
    end

    # The email exactly as a follower gets it (for the page's preview frame).
    def preview
      message = FollowerMailer.preview(@email, Current.user.person&.name.to_s.split.first).message
      html = message.html_part ? message.html_part.body.decoded : message.body.decoded
      render html: html.html_safe, layout: false
    end

    def test
      FollowerMailer.test_email(@email, Current.user).deliver_later
      redirect_to manage_edit_follower_email_path(@email), notice: "A test is on its way to #{Current.user.email_address}."
    end

    def deliver
      FollowerEmailSender.send!(@email, Current.user)
      redirect_to manage_follower_email_path(@email), notice: "Sending to #{ActionController::Base.helpers.pluralize(@email.recipient_count, 'person')}."
    rescue FollowerEmailSender::Error => e
      redirect_to manage_edit_follower_email_path(@email), alert: e.message
    end

    def show
      return redirect_to(manage_edit_follower_email_path(@email)) if @email.draft?

      @counts = @email.counts
      @sales_rows = FollowerEmailSales.by_show(@email)
      @sales = FollowerEmailSales.for(Current.organization, [ @email ])[@email.id] || { tickets: 0, cents: 0 }
      @unsubscribed = Follower.where(id: @email.follower_email_deliveries.select(:follower_id), status: "unsubscribed")
                              .where("followers.unsubscribed_at >= ?", @email.sent_at).count
    end

    private

    def set_email
      @email = Current.organization.follower_emails.find(params[:id])
    end

    def announce_show
      return nil if params[:show_id].blank?

      Show.joins(:production).includes(:production).find_by(productions: { organization_id: Current.organization.id }, id: params[:show_id])
    end

    def load_choices
      @lists = Current.organization.mailing_lists.active.main_first.to_a
      @list_counts = MailingListMembership.joins(:follower).where(mailing_list_id: @lists.map(&:id), followers: { status: "subscribed" })
                                          .group(:mailing_list_id).count
      @segments = Current.organization.segments.order(:name).to_a
      @upcoming_shows = Show.joins(:production).includes(:production, :ticket_listing)
                            .where(productions: { organization_id: Current.organization.id }, canceled: false)
                            .where(date_and_time: Time.current..).order(:date_and_time).limit(40).to_a
      chosen = @email.shows.map(&:id)
      @upcoming_shows = (@email.shows + @upcoming_shows.reject { |show| chosen.include?(show.id) })
    end
  end
end
