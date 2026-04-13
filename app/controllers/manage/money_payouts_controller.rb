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

      # Send reminder messages to each person (message-only, no email)
      sent_count = 0
      missing_people.each do |person|
        next unless person.user.present?

        rendered = ContentTemplateService.render("payment_setup_reminder", {
          person_name: person.first_name || "there",
          organization_name: Current.organization.name,
          custom_message: body_html
        })

        MessageService.send_direct(
          sender: Current.user,
          recipient_person: person,
          subject: rendered[:subject],
          body: rendered[:body],
          production: @production,
          organization: Current.organization
        )

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

      # Apply filter parameter
      @filter = params[:filter].presence || "all"

      # Build database query with filtering at DB level
      query =  @production.shows.order(date_and_time: :desc)

      # Apply date filter
      if @hide_future_events
        query = query.where("date_and_time <= ?", 1.day.from_now)
      end

      # Apply event type filter - always exclude non-revenue event types unless specifically requested
      revenue_types = EventTypes.revenue_event_types
      unless @filter == "all"
        query = query.where(event_type: revenue_types)
      end

      # Apply payout status filter
      query = case @filter
      when "awaiting_calculation"
                query.where(event_type: revenue_types)
                     .left_joins(:show_payout)
                     .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
      when "awaiting_payout"
                query.joins(:show_payout)
                     .where(show_payouts: { status: "awaiting_payout" })
                     .where.not(show_payouts: { calculated_at: nil })
      when "paid"
                query.joins(:show_payout)
                     .where(show_payouts: { status: "paid" })
      else
                # Default: show revenue events only
                query.where(event_type: revenue_types)
      end

      # Load shows with pre-fetched associations
      @shows = query
               .includes(:show_financials, :show_payout, :location, show_payout: :show_payout_line_items)
               .limit(100)
               .to_a

      # Summary stats for production
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
      # Show all productions the user has access to (excludes courses which use different scheduling)
      @productions = Current.user.accessible_productions.where.not(production_type: "course").order(:name)
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
        paid_amount: paid_payouts.sum(:total_payout) || 0,
        outstanding_advances: production.person_advances.not_settled.sum(:remaining_balance),
        total_advances: production.person_advances.sum(:original_amount)
      }
    end

    def people_missing_payment_info
      productions = @production ? [ @production ] : Current.user.accessible_productions

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
