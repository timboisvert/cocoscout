# frozen_string_literal: true

module Manage
  class MoneyPayoutsController < Manage::ManageController
    include Rails.application.routes.url_helpers
    before_action :set_production

    def index
      if @production
        # Single production view - show list of shows
        load_production_shows
      else
        # All productions view - show list of productions with summaries
        load_all_productions
      end

      # Set up email draft for payment setup reminder modal
      @payment_reminder_email_draft = EmailDraft.new(
        title: default_payment_reminder_subject,
        body: default_payment_reminder_body
      )
    end

    def send_payment_setup_reminders
      missing_people = people_missing_payment_info

      if missing_people.empty?
        redirect_to manage_money_production_payouts_path(@production),
                    alert: "No people missing payment information."
        return
      end

      # Get the email content from the form
      subject = params.dig(:email_draft, :title)
      body_html = params.dig(:email_draft, :body)

      if subject.blank? || body_html.blank?
        redirect_to manage_money_production_payouts_path(@production),
                    alert: "Subject and message are required."
        return
      end

      # Prepend organization name to subject
      org_name = Current.organization.name
      full_subject = "[#{org_name}] #{subject}"

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
          Current.organization,
          full_subject,
          body_html,
          email_batch_id: email_batch.id
        ).deliver_later

        sent_count += 1
      end

      redirect_to manage_money_production_payouts_path(@production),
                  notice: "Payment setup reminders sent to #{sent_count} #{"person".pluralize(sent_count)}."
    end

    private

    def set_production
      if params[:production_id].present?
        @production = Current.organization.productions.find_by(id: params[:production_id])
      end
    end

    def load_production_shows
      # Handle hide_future_events toggle (enabled by default - future events hidden)
      if params[:hide_future_events].present?
        @hide_future_events = params[:hide_future_events] == "true"
        cookies[:money_hide_future_events] = { value: @hide_future_events.to_s, expires: 1.year.from_now }
      else
        @hide_future_events = cookies[:money_hide_future_events] != "false"
      end

      # Handle hide_non_revenue toggle (enabled by default)
      if params[:hide_non_revenue].present?
        @hide_non_revenue = params[:hide_non_revenue] == "true"
        cookies[:money_hide_non_revenue] = { value: @hide_non_revenue.to_s, expires: 1.year.from_now }
      else
        @hide_non_revenue = cookies[:money_hide_non_revenue] != "false"
      end

      # Build query based on hide future events toggle
      if @hide_future_events
        @shows = @production.shows
                            .where("date_and_time <= ?", 1.day.from_now)
                            .order(date_and_time: :desc)
                            .includes(:show_financials, :show_payout, :location)
                            .limit(100)
                            .to_a
      else
        @shows = @production.shows
                            .order(date_and_time: :desc)
                            .includes(:show_financials, :show_payout, :location)
                            .limit(100)
                            .to_a
      end

      # Apply filter
      @filter = params[:filter].presence || "all"
      @shows = apply_filter(@shows, @filter)

      if @hide_non_revenue
        @shows = @shows.select { |show| EventTypes.revenue_event_types.include?(show.event_type) }
      end

      # Summary stats for production
      revenue_types = EventTypes.revenue_event_types
      revenue_shows = @production.shows.where(event_type: revenue_types).where("date_and_time <= ?", 1.day.from_now)

      @needs_calculation_count = revenue_shows.left_joins(:show_payout)
                                               .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
                                               .count

      awaiting_payouts = @production.show_payouts.where(status: "awaiting_payout").where.not(calculated_at: nil)
      @awaiting_payout_count = awaiting_payouts.count
      @total_awaiting_payout = awaiting_payouts.sum(:total_payout) || 0
      @awaiting_payout_people_count = ShowPayoutLineItem.where(show_payout: awaiting_payouts)
                                                         .not_already_paid
                                                         .count

      paid_payouts = @production.show_payouts.paid
      @paid_shows_count = paid_payouts.count
      @total_paid = paid_payouts.sum(:total_payout) || 0
      @paid_people_count = ShowPayoutLineItem.where(show_payout: paid_payouts)
                                              .already_paid
                                              .count

      @missing_payment_info = people_missing_payment_info
    end

    def load_all_productions
      # Only show in-house productions on the payouts page (not third-party/renters)
      @productions = Current.organization.productions.where.not(production_type: "third_party").order(:name)
      @production_summaries = @productions.map do |production|
        build_payout_summary(production)
      end

      # Organization-wide stats
      all_awaiting = @production_summaries.sum { |s| s[:awaiting_payout_amount] }
      all_paid = @production_summaries.sum { |s| s[:paid_amount] }
      all_awaiting_count = @production_summaries.sum { |s| s[:awaiting_payout_count] }
      all_paid_count = @production_summaries.sum { |s| s[:paid_count] }

      @org_awaiting_payout = all_awaiting
      @org_paid = all_paid
      @org_awaiting_count = all_awaiting_count
      @org_paid_count = all_paid_count

      @missing_payment_info = []
    end

    def build_payout_summary(production)
      revenue_types = EventTypes.revenue_event_types
      revenue_shows = production.shows.where(event_type: revenue_types).where("date_and_time <= ?", 1.day.from_now)

      # Get financial summary for consistent data
      financial_summary = FinancialSummaryService.new(production).summary_for_period(:all_time)

      awaiting_payout = production.show_payouts.where(status: "awaiting_payout").where.not(calculated_at: nil)
      paid_payouts = production.show_payouts.paid

      needs_calculation = revenue_shows.left_joins(:show_payout)
                                       .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
                                       .count

      {
        production: production,
        revenue_shows: revenue_shows.count,
        gross_revenue: financial_summary[:gross_revenue],
        show_expenses: financial_summary[:show_expenses],
        total_payouts: financial_summary[:total_payouts],
        net_income: financial_summary[:net_income],
        needs_calculation_count: needs_calculation,
        awaiting_payout_count: awaiting_payout.count,
        awaiting_payout_amount: awaiting_payout.sum(:total_payout) || 0,
        paid_count: paid_payouts.count,
        paid_amount: paid_payouts.sum(:total_payout) || 0
      }
    end

    def apply_filter(scope, filter)
      revenue_types = EventTypes.revenue_event_types

      case filter
      when "awaiting_calculation"
        scope.select do |show|
          revenue_types.include?(show.event_type) &&
          (show.show_payout.nil? || show.show_payout.calculated_at.nil?)
        end
      when "awaiting_payout"
        scope.select { |show| show.show_payout&.status == "awaiting_payout" && show.show_payout.calculated_at.present? }
      when "paid"
        scope.select { |show| show.show_payout&.status == "paid" }
      else
        # Only show revenue events by default for payouts
        scope.select { |show| revenue_types.include?(show.event_type) }
      end
    end

    def people_missing_payment_info
      productions = @production ? [ @production ] : Current.organization.productions

      awaiting_payout_ids = productions.flat_map { |prod| prod.show_payouts.where(status: "awaiting_payout").pluck(:id) }

      return [] if awaiting_payout_ids.empty?

      # Get people from line items that aren't already paid
      # Explicitly exclude guest line items (is_guest: true) - they have separate payment handling
      person_ids = ShowPayoutLineItem.where(show_payout_id: awaiting_payout_ids)
                                      .where(payee_type: "Person")
                                      .where(is_guest: [ false, nil ])
                                      .not_already_paid
                                      .pluck(:payee_id)
                                      .uniq

      Person.where(id: person_ids)
            .select { |p| !p.venmo_configured? && !p.zelle_configured? }
    end

    def default_payment_reminder_subject
      ContentTemplateService.render_subject("payment_setup_reminder", {
        production_name: Current.organization.name
      })
    end

    def default_payment_reminder_body
      ContentTemplateService.render_body("payment_setup_reminder", {
        production_name: Current.organization.name,
        payment_setup_url: my_payments_setup_url
      })
    end
  end
end
