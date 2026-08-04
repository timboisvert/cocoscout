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
      # Show all productions the user has access to (excludes courses which use different scheduling)
      @productions = Current.user.accessible_productions.schedulable.order(:name)
      @production_summaries = @productions.map { |p| build_payout_summary(p) }

      # "Awaiting Payout" — everything we still need to pay, across productions,
      # courses, and contracts. This is the address-first to-do list.
      @awaiting_items = build_awaiting_payout_items

      # Runs already in motion — submitted money the org is waiting on (ACH
      # clearing, or partially paid runs waiting on people's bank info).
      @in_flight_runs = Current.organization.payout_batches
                               .where(status: %w[funding funded processing partially_paid])
                               .recent.to_a

      # Payouts blocked on the payee: people owed money who haven't set up
      # payment info yet, across all productions.
      @missing_payment_info = people_missing_payment_info
    end

    def build_payout_summary(production)
      revenue_types = EventTypes.revenue_event_types
      revenue_shows = production.shows.where(event_type: revenue_types).where("date_and_time <= ?", 1.day.from_now)

      # Get financial summary for consistent data
      financial_summary = FinancialSummaryService.new(production).summary_for_period(:all_time)

      needs_calculation = revenue_shows.left_joins(:show_payout)
                                       .where("show_payouts.id IS NULL OR show_payouts.calculated_at IS NULL")
                                       .count

      # Amounts from line items (paid vs unpaid); show counts stay show-level.
      amounts = net_payout_amounts(production)

      {
        production: production,
        revenue_shows: revenue_shows.count,
        gross_revenue: financial_summary[:gross_revenue],
        show_expenses: financial_summary[:show_expenses],
        total_payouts: financial_summary[:total_payouts],
        net_income: financial_summary[:net_income],
        needs_calculation_count: needs_calculation,
        awaiting_payout_count: production.show_payouts.where(status: "awaiting_payout").where.not(calculated_at: nil).count,
        awaiting_payout_amount: amounts[:awaiting_amount],
        awaiting_in_run_amount: amounts[:in_run_amount],
        paid_count: production.show_payouts.paid.count,
        paid_amount: amounts[:paid_amount],
        outstanding_advances: production.person_advances.not_settled.sum(:remaining_balance),
        total_advances: production.person_advances.sum(:original_amount)
      }
    end

    # The heterogeneous "to pay" list: productions with unpaid performer payouts,
    # courses with unpaid instructor payouts, and contracts with outstanding
    # outgoing payments. Each item carries a per-status breakdown (to pay / in
    # draft run / in flight / paid) so the grid can answer "what have I actually
    # done about this?" per row. Most-actionable first.
    def build_awaiting_payout_items
      items = []

      @production_summaries.each do |s|
        next unless s[:awaiting_payout_amount].to_f.positive?

        shows = awaiting_shows_for(s[:production])
        next if shows.empty?

        breakdown = helpers.awaiting_payout_breakdown(shows.flat_map { |sh| sh.show_payout.line_items })
        amounts = breakdown[:amounts]
        counts = breakdown[:counts]
        # Say what state the money is in, not just that it exists: people still
        # needing action, people queued in runs, people already paid.
        parts = [ "#{shows.size} #{'show'.pluralize(shows.size)}" ]
        parts << "#{counts[:to_pay]} #{'person'.pluralize(counts[:to_pay])} to pay" if counts[:to_pay].positive?
        parts << "#{counts[:in_draft]} in a draft run" if counts[:in_draft].positive?
        parts << "#{counts[:in_flight]} in flight" if counts[:in_flight].positive?
        parts << "#{counts[:paid]} already paid" if counts[:paid].positive?

        items << {
          name: s[:production].name, kind: :production,
          amount: amounts[:to_pay] + amounts[:in_draft] + amounts[:in_flight],
          amounts: amounts,
          subtitle: parts.join(" · "),
          production: s[:production],
          awaiting_shows: shows
        }
      end

      Current.user.accessible_productions.courses
             .includes(course_offerings: { course_offering_payout: :line_items }).each do |course|
        # One course can hold many runs — surface each run's own payout. Course
        # instructor payouts are settled directly (never staged in a run).
        course.course_offerings.each do |offering|
          payout = offering.course_offering_payout
          next unless payout

          unpaid = payout.line_items.reject(&:paid?)
          paid = payout.line_items.select(&:paid?)
          amount = unpaid.sum(&:amount_cents) / 100.0
          next unless amount.positive?

          subtitle = +"#{unpaid.count} instructor #{'payout'.pluralize(unpaid.count)} to pay"
          subtitle << " · #{paid.count} already paid" if paid.any?

          items << {
            name: offering.title, kind: :course, amount: amount,
            amounts: { to_pay: amount, paid: paid.sum(&:amount_cents) / 100.0 },
            subtitle: subtitle,
            href: manage_course_offering_payout_path(offering)
          }
        end
      end

      Current.organization.contracts
             .includes({ contract_payments: { payout_contribution: :payout_batch } }, :contractor).each do |contract|
        outgoing = contract.contract_payments.select(&:direction_outgoing?)
        pending = outgoing.select(&:status_pending?)
        amount = pending.sum { |p| p.amount.to_f }
        next unless amount.positive?

        # Contract payments can be staged in payout runs too — split them the
        # same way as show payouts.
        by_col = pending.group_by do |p|
          batch = p.payout_contribution&.payout_batch
          if batch&.status == "draft"
            :in_draft
          elsif batch && PayoutBatchService::UNSETTLED_BATCH_STATUSES.include?(batch.status)
            :in_flight
          else
            :to_pay
          end
        end
        paid_payments = outgoing.select(&:status_paid?)
        amounts = by_col.transform_values { |ps| ps.sum { |p| p.amount.to_f } }
        amounts[:paid] = paid_payments.sum { |p| p.amount.to_f }

        parts = [ "#{pending.count} contract #{'payment'.pluralize(pending.count)} due" ]
        due = pending.filter_map(&:due_date).min
        if due
          due_label = pending.size == 1 ? "due" : "next due"
          parts << (due < Date.current ? "overdue since #{due.strftime('%b %-d')}" : "#{due_label} #{due.strftime('%b %-d')}")
        end
        parts << "#{by_col[:in_draft].size} in a draft run" if by_col[:in_draft].present?
        parts << "#{by_col[:in_flight].size} in flight" if by_col[:in_flight].present?
        parts << "#{paid_payments.count} already paid" if paid_payments.any?

        items << {
          name: contract.contractor_name, kind: :contract, amount: amount,
          amounts: amounts,
          subtitle: parts.join(" · "),
          href: manage_contract_path(contract)
        }
      end

      # Rows needing the most action float to the top.
      items.sort_by! { |i| [ -i[:amounts][:to_pay].to_f, -i[:amount].to_f ] }

      # Which status columns the grid needs: "To pay" always; the others only
      # when some row actually has money there.
      @awaiting_columns = [ :to_pay ]
      %i[in_draft in_flight paid].each do |col|
        @awaiting_columns << col if items.any? { |i| i[:amounts][col].to_f > 0.004 }
      end

      # Link the production rows now that the column set is known — the accordion
      # gets it via the URL so its inline show rows line up with the grid. Go
      # straight to the payout that needs attention: one awaiting show → link
      # right to it; several → an accordion, each linking to its show payout.
      cols_param = @awaiting_columns.join(",")
      items.each do |item|
        shows = item.delete(:awaiting_shows) || next
        production = item.delete(:production)
        if shows.size == 1
          item[:href] = manage_money_show_payout_path(shows.first)
        else
          item[:expand_src] = manage_money_production_payout_events_path(production, awaiting: 1, cols: cols_param)
          item[:expand_id] = "awaiting-events-#{production.id}"
        end
      end

      items
    end

    # The shows in a production that still have someone unpaid, with line items
    # (and their payout-run batches) loaded for the status breakdown.
    def awaiting_shows_for(production)
      calculated_ids = production.show_payouts.where.not(calculated_at: nil).select(:id)
      unpaid_payout_ids = ShowPayoutLineItem.where(show_payout_id: calculated_ids).unpaid.distinct.pluck(:show_payout_id)
      return [] if unpaid_payout_ids.empty?

      show_ids = ShowPayout.where(id: unpaid_payout_ids).pluck(:show_id)
      Show.where(id: show_ids)
          .includes(show_payout: { line_items: { payout_contribution: :payout_batch } })
          .order(date_and_time: :desc).to_a
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
