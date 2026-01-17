# frozen_string_literal: true

module Manage
  class MoneyPayoutsController < Manage::ManageController
    include Rails.application.routes.url_helpers
    before_action :set_production

    def index
      @payout_schemes = @production.payout_schemes.default_first
      @default_scheme = @payout_schemes.find(&:is_default)

      # Get shows with payout status - include all past events
      @shows = @production.shows
                          .where("date_and_time <= ?", 1.day.from_now)
                          .order(date_and_time: :desc)
                          .includes(:show_financials, :show_payout, :location)
                          .limit(50)

      # Apply filter if provided
      @filter = params[:filter].presence || "all"
      @shows = apply_filter(@shows, @filter)

      # Persist hide_non_revenue preference in cookie
      if params[:hide_non_revenue].present?
        @hide_non_revenue = params[:hide_non_revenue] == "true"
        cookies[:money_hide_non_revenue] = { value: @hide_non_revenue.to_s, expires: 1.year.from_now }
      else
        @hide_non_revenue = cookies[:money_hide_non_revenue] != "false"
      end

      # Filter out non-revenue events if toggle is on
      if @hide_non_revenue
        @shows = @shows.where(event_type: EventTypes.revenue_event_types)
      end

      # Summary stats - payout focused
      revenue_types = EventTypes.revenue_event_types
      revenue_shows = @production.shows.where(event_type: revenue_types).where("date_and_time <= ?", 1.day.from_now)

      # Awaiting calculation: shows that need data or haven't been calculated
      @needs_calculation_count = revenue_shows.left_joins(:show_payout)
                                              .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
                                              .count

      # Awaiting payout: calculated but not fully paid
      awaiting_payouts = @production.show_payouts.where(status: "awaiting_payout")
                                                  .where.not(calculated_at: nil)
      @awaiting_payout_count = awaiting_payouts.count
      @total_awaiting_payout = awaiting_payouts.sum(:total_payout) || 0
      @awaiting_payout_people_count = ShowPayoutLineItem.where(show_payout: awaiting_payouts)
                                                         .not_already_paid
                                                         .count

      # Paid out
      paid_payouts = @production.show_payouts.paid
      @paid_shows_count = paid_payouts.count
      @total_paid = paid_payouts.sum(:total_payout) || 0
      @paid_people_count = ShowPayoutLineItem.where(show_payout: paid_payouts)
                                              .already_paid
                                              .count

      # People missing payment info
      @missing_payment_info = people_missing_payment_info

      # Set up email draft for payment setup reminder modal
      @payment_reminder_email_draft = EmailDraft.new(
        title: default_payment_reminder_subject,
        body: default_payment_reminder_body
      )
    end

    def send_payment_setup_reminders
      missing_people = people_missing_payment_info

      if missing_people.empty?
        redirect_to manage_production_money_payouts_path(@production),
                    alert: "No people missing payment information."
        return
      end

      # Get the email content from the form
      subject = params.dig(:email_draft, :title)
      body_html = params.dig(:email_draft, :body)

      if subject.blank? || body_html.blank?
        redirect_to manage_production_money_payouts_path(@production),
                    alert: "Subject and message are required."
        return
      end

      # Prepend production name to subject
      full_subject = "[#{@production.name}] #{subject}"

      # Create email batch for tracking
      email_batch = EmailBatch.create!(
        user: Current.user,
        subject: full_subject,
        recipient_count: missing_people.count { |p| p.email.present? },
        sent_at: Time.current
      )

      # Send reminder emails to each person
      sent_count = 0
      missing_people.each do |person|
        next unless person.email.present?

        Manage::PaymentMailer.payment_setup_reminder(
          person,
          @production,
          full_subject,
          body_html,
          email_batch_id: email_batch.id
        ).deliver_later

        sent_count += 1
      end

      redirect_to manage_production_money_payouts_path(@production),
                  notice: "Payment setup reminders sent to #{sent_count} #{"person".pluralize(sent_count)}."
    end

    private

    def set_production
      @production = Current.production
      redirect_to select_production_path unless @production
    end

    def apply_filter(scope, filter)
      case filter
      when "awaiting_calculation"
        # Revenue events with financial data but not yet calculated
        revenue_types = EventTypes.revenue_event_types
        scope.where(event_type: revenue_types)
             .left_joins(:show_payout)
             .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
      when "awaiting_payout"
        scope.joins(:show_payout)
             .where(show_payouts: { status: "awaiting_payout" })
             .where.not(show_payouts: { calculated_at: nil })
      when "paid"
        scope.joins(:show_payout).where(show_payouts: { status: "paid" })
      else
        # Only show revenue events by default for payouts
        revenue_types = EventTypes.revenue_event_types
        scope.where(event_type: revenue_types)
      end
    end

    def people_missing_payment_info
      # Get all people who have line items awaiting payout but no payment info
      awaiting_payout_ids = @production.show_payouts
                                        .where(status: "awaiting_payout")
                                        .pluck(:id)

      return [] if awaiting_payout_ids.empty?

      person_ids = ShowPayoutLineItem.where(show_payout_id: awaiting_payout_ids)
                                      .where(payee_type: "Person")
                                      .not_already_paid
                                      .pluck(:payee_id)
                                      .uniq

      Person.where(id: person_ids)
            .select { |p| !p.venmo_configured? && !p.zelle_configured? }
    end

    def default_payment_reminder_subject
      EmailTemplateService.render_subject_without_prefix("payment_setup_reminder", {
        production_name: @production.name
      })
    end

    def default_payment_reminder_body
      EmailTemplateService.render_body("payment_setup_reminder", {
        production_name: @production.name,
        payment_setup_url: my_payments_setup_url
      })
    end
  end
end
