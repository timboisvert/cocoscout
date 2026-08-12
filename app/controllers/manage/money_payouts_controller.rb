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

    # The full every-production payout grid, moved off the index so the main
    # payouts page stays focused on what needs action.
    def all
      @productions = Current.user.accessible_productions.schedulable.order(:name)
      @production_summaries = @productions.map { |p| build_payout_summary(p) }
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

    # Slim inline list of a production's shows + their payout status, loaded lazily
    # into the accordion on the payouts list (Turbo frame).
    def events
      return head :not_found unless @production

      revenue_types = EventTypes.revenue_event_types
      shows = @production.shows.where(event_type: revenue_types)
                         .includes(:show_payout, show_payout: { line_items: { payout_contribution: :payout_batch } })
                         .order(date_and_time: :desc)
                         .limit(100)
                         .select { |s| s.show_payout&.calculated_at.present? }
      # The Awaiting-Payout accordion only wants shows that still owe someone, and
      # mirrors that section's status columns — the parent passes which ones it's
      # showing so the inline rows line up under its headers.
      @awaiting_only = params[:awaiting].present?
      shows = shows.select { |s| s.show_payout.line_items.any? { |li| !li.paid? } } if @awaiting_only
      @awaiting_cols = params[:cols].to_s.split(",").map(&:to_sym) &
                       Manage::MoneyPayoutsHelper::AWAITING_PAYOUT_COLUMNS.keys
      @awaiting_cols = [ :to_pay ] if @awaiting_cols.empty?
      @shows = shows
      render layout: false
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
               .includes(:show_financials, :show_payout, :location,
                         show_payout: { line_items: { payout_contribution: :payout_batch } })
               .limit(100)
               .to_a

      # Summary stats for production
      revenue_shows = @production.shows.where(event_type: revenue_types).where("date_and_time <= ?", 1.day.from_now)

      @needs_calculation_count = revenue_shows.left_joins(:show_payout)
                                               .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
                                               .count

      # Amounts and people come from the LINE ITEMS (paid vs unpaid), not the
      # show's coarse total — so partially-paid shows show the right remaining.
      amounts = net_payout_amounts(@production)
      @total_awaiting_payout = amounts[:awaiting_amount]
      @total_awaiting_in_run = amounts[:in_run_amount]
      @total_paid = amounts[:paid_amount]
      @awaiting_payout_people_count = amounts[:awaiting_people]
      @paid_people_count = amounts[:paid_people]

      # Show counts stay at the show level (a partially-paid show is still awaiting).
      @awaiting_payout_count = @production.show_payouts.where(status: "awaiting_payout").where.not(calculated_at: nil).count
      @paid_shows_count = @production.show_payouts.paid.count

      @missing_payment_info = people_missing_payment_info

      # Prioritised lists (address-first), replacing the status filter:
      #   1. still needs calculating, 2. calculated but someone's unpaid, 3. all.
      revenue_types = EventTypes.revenue_event_types
      all_revenue_shows = @production.shows.where(event_type: revenue_types)
                                     .where("date_and_time <= ?", 1.day.from_now)
                                     .includes(:show_financials, :show_payout,
                                               show_payout: { line_items: { payout_contribution: :payout_batch } })
                                     .order(date_and_time: :desc).to_a
      @awaiting_calculation_shows = all_revenue_shows.select { |s| s.show_payout.nil? || s.show_payout.calculated_at.nil? }
      @awaiting_payout_shows = all_revenue_shows.select do |s|
        s.show_payout&.calculated_at && s.show_payout.line_items.any? { |li| !li.paid? }
      end
      @all_payout_shows = all_revenue_shows
    end

    def load_all_productions
      # "Awaiting Payout" — everything we still need to pay, across productions,
      # courses, and contracts. This is the action-first to-do list, and it's the
      # same object the Money hub summarises, so the two can't disagree.
      @todo = MoneyTodoService.new(user: Current.user, organization: Current.organization)
      @awaiting_items = @todo.payouts.items
      @awaiting_columns = @todo.payouts.columns

      # Every run still moving money — drafts not yet submitted, ACH clearing,
      # or partially paid runs waiting on people's bank info. Drafts show here
      # too so the state boxes up top always have a matching row on this page.
      @active_runs = Current.organization.payout_batches
                            .where(status: PayoutBatchService::UNSETTLED_BATCH_STATUSES)
                            .recent.to_a

      # Money-by-state totals for the summary boxes, split by what still has to
      # happen to it. Summed from the same runs the Active Runs list renders —
      # a partially paid run counts only its unpaid remainder.
      @run_state_cents = {
        draft: @active_runs.select { |r| r.status == "draft" }.sum(&:total_cents),
        funding: @active_runs.select { |r| %w[funding funded processing].include?(r.status) }.sum(&:total_cents),
        waiting: @active_runs.select { |r| r.status == "partially_paid" }
                             .sum { |r| r.total_cents - r.paid_total_cents }
      }

      # Payouts blocked on the payee: people owed money who haven't set up
      # payment info yet, across all productions.
      @missing_payment_info = people_missing_payment_info
    end

    # One row of the All Payouts grid. Only what that grid renders: awaiting and
    # paid money, and the two counts beside them.
    #
    # This used to run a whole FinancialSummaryService pass per production — a
    # query for every show — plus counts of revenue shows, shows needing
    # calculation, and two advance sums. None of it reached the page: the keys
    # were read by _production_row.html.erb, which nothing renders any more.
    def build_payout_summary(production)
      amounts = net_payout_amounts(production)

      {
        production: production,
        awaiting_payout_count: production.show_payouts.where(status: "awaiting_payout").where.not(calculated_at: nil).count,
        awaiting_payout_amount: amounts[:awaiting_amount],
        awaiting_in_run_amount: amounts[:in_run_amount],
        paid_count: production.show_payouts.paid.count,
        paid_amount: amounts[:paid_amount]
      }
    end

    # Awaiting/paid payout money and people for a production, computed from the
    # LINE ITEMS (each person's net), so a partially-paid show reflects only its
    # remaining unpaid people — not the show's full total. `in_run_amount` is the
    # slice of the awaiting money already staged in an open/in-flight payout run:
    # still unpaid, but queued to move — so "awaiting $100, $50 in a run" reads
    # as "only $50 still needs your action".
    def net_payout_amounts(production)
      calculated_ids = production.show_payouts.where.not(calculated_at: nil).select(:id)
      items = ShowPayoutLineItem.where(show_payout_id: calculated_ids)
      net = Arel.sql("COALESCE(show_payout_line_items.amount, 0) - COALESCE(show_payout_line_items.advance_deduction, 0)")
      {
        awaiting_amount: items.unpaid.sum(net),
        in_run_amount: items.unpaid.joins(payout_contribution: :payout_batch)
                            .where(payout_batches: { status: PayoutBatchService::UNSETTLED_BATCH_STATUSES })
                            .sum(net),
        paid_amount: items.paid.sum(net),
        awaiting_people: items.unpaid.count,
        paid_people: items.paid.count
      }
    end

    def people_missing_payment_info
      production_ids = @production ? [ @production.id ] : Current.user.accessible_productions.pluck(:id)

      # One query across every production, not one per production.
      awaiting_payout_ids = ShowPayout.joins(:show)
                                      .where(shows: { production_id: production_ids }, status: "awaiting_payout")
                                      .pluck(:id)

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
            .reject(&:can_receive_payouts?)
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
