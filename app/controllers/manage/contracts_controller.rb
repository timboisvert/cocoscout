# frozen_string_literal: true

module Manage
  class ContractsController < ManageController
    before_action :set_contract, except: %i[index new create completed]

    def index
      @contracts = Current.organization.contracts.includes(:contract_payments, :space_rentals)

      # Active and completed contracts ordered by start date
      @active_contracts = @contracts.status_active.order(:contract_start_date)
      @draft_contracts = @contracts.status_draft
      @completed_contracts = @contracts.status_completed.or(@contracts.status_cancelled).order(contract_end_date: :desc)

      # Sort all contracts for the combined list (active + draft)
      # Active contracts by start date, then drafts with dates, then drafts without dates
      @sorted_contracts = (
        @active_contracts.to_a +
        @draft_contracts.where.not(contract_start_date: nil).order(:contract_start_date).to_a +
        @draft_contracts.where(contract_start_date: nil).order(:created_at).to_a
      )

      active_contract_ids = @active_contracts.map(&:id)

      # Month navigation for the unified calendar. Past months stay reachable so
      # overdue payments and earlier events are never hidden.
      @current_month = if params[:month].present?
        Date.parse(params[:month]).in_time_zone.beginning_of_month
      else
        Time.current.beginning_of_month
      end
      @prev_month = @current_month - 1.month
      @next_month = @current_month + 1.month
      @can_go_prev = true
      @can_go_next = true

      month_start = @current_month.to_date
      month_end = @current_month.end_of_month.to_date
      window_start = month_start.beginning_of_day
      window_end = month_end.end_of_day

      # Unified calendar items: space rentals (when the space is booked) + payments
      # (when money is due), bucketed by date. We intentionally do NOT plot the
      # Shows tied to a booking — each contract booking is a SpaceRental with a
      # linked Show, so plotting both double-listed every booking.
      #
      # When a payment is due on the same day as a rental for the same contract, we
      # fold it onto the rental card instead of adding a separate payment pill.
      @calendar_items_by_date = Hash.new { |h, k| h[k] = [] }

      payments = ContractPayment
        .joins(:contract)
        .includes(:contract)
        .where(contracts: { organization_id: Current.organization.id, status: "active" })
        .where(due_date: month_start..month_end)
        .to_a

      # Group payments by [contract_id, date] so rentals can claim same-day payments.
      payments_by_contract_date = payments.group_by { |p| [ p.contract_id, p.due_date ] }
      claimed_keys = Set.new

      SpaceRental
        .where(contract_id: active_contract_ids)
        .where(starts_at: window_start..window_end)
        .includes(:contract, :location)
        .find_each do |rental|
          key = [ rental.contract_id, rental.starts_at.to_date ]
          # Only the first rental for a contract+date claims that day's payments,
          # so an amount is never shown twice.
          rental_payments = claimed_keys.add?(key) ? (payments_by_contract_date[key] || []) : []
          @calendar_items_by_date[rental.starts_at.to_date] << {
            type: :rental,
            sort_key: [ 1, rental.starts_at ],
            at: rental.starts_at,
            record: rental,
            contract: rental.contract,
            payments: rental_payments
          }
        end

      # Remaining payments (no rental on the same contract+day) render on their own.
      payments_by_contract_date.each do |key, pmts|
        next if claimed_keys.include?(key)
        pmts.each do |payment|
          @calendar_items_by_date[payment.due_date] << {
            type: :payment,
            sort_key: [ 0, payment.due_date.to_time ],
            record: payment,
            contract: payment.contract,
            late: payment.overdue?,
            incoming: payment.direction_incoming?
          }
        end
      end

      @calendar_items_by_date.each_value { |items| items.sort_by! { |i| i[:sort_key] } }

      # Count of overdue payments across all months (may fall outside the visible
      # month) so we can surface a persistent late-payments warning.
      @late_payments_count = ContractPayment
        .joins(:contract)
        .where(contracts: { organization_id: Current.organization.id, status: "active" })
        .where(status: "pending")
        .where("due_date < ?", Date.current)
        .count

      # Contract stats for this year
      year_start = Date.current.beginning_of_year
      year_end = Date.current.end_of_year

      # All payments for active/completed contracts this year (incoming only)
      year_payments = ContractPayment
        .joins(:contract)
        .where(contracts: { organization_id: Current.organization.id })
        .where.not(contracts: { status: %w[draft cancelled] })
        .where(direction: "incoming")

      # Money received (paid incoming payments this year)
      @money_received = year_payments
        .where(status: "paid")
        .where("contract_payments.updated_at >= ? AND contract_payments.updated_at <= ?", year_start, year_end)
        .where.not(amount: nil)
        .sum(:amount)

      # Money remaining (pending incoming payments)
      @money_remaining = year_payments
        .where(status: "pending")
        .where.not(amount: nil)
        .sum(:amount)

      # Total contract value (all incoming payments from contracts starting this year)
      @total_contract_value = ContractPayment
        .joins(:contract)
        .where(contracts: { organization_id: Current.organization.id })
        .where.not(contracts: { status: %w[draft cancelled] })
        .where("contracts.contract_start_date >= ? AND contracts.contract_start_date <= ?", year_start, year_end)
        .where(direction: "incoming")
        .where.not(amount: nil)
        .sum(:amount)

      # Projected revenue from rev-share contracts (midpoint of projections)
      rev_share_contracts = Current.organization.contracts
        .where.not(status: %w[draft cancelled])
        .where("contracts.contract_start_date >= ? AND contracts.contract_start_date <= ?", year_start, year_end)
        .select { |c| c.revenue_share? && c.has_revenue_projection? }

      @projected_revenue_low = rev_share_contracts.sum { |c| c.projected_our_revenue_range&.dig(:low) || 0 }
      @projected_revenue_high = rev_share_contracts.sum { |c| c.projected_our_revenue_range&.dig(:high) || 0 }
      @has_projections = rev_share_contracts.any?
    end

    def completed
      @completed_contracts = Current.organization.contracts
        .includes(:contract_payments, :space_rentals)
        .status_completed
        .or(Current.organization.contracts.status_cancelled)
        .order(contract_end_date: :desc)
    end

    def show
      # In-progress drafts are edited in the wizard. But an e-sign contract that's
      # been signed/sent (awaiting_send / out_for_signature) is viewable here —
      # read-only, so you can see its status and revoke — even though it's still
      # technically a draft until the counterparty signs.
      if @contract.status_draft? && (!@contract.signing_mode_esign? || @contract.signing_unsent?)
        redirect_to manage_resume_contract_wizard_path(@contract) and return
      end

      # Generate the signed PDF if it's executed but doesn't have one yet
      # (covers contracts signed before PDF generation existed).
      @contract.ensure_signed_pdf!

      # Sync any paid course offering payouts to contract payments
      @contract.sync_course_payouts_to_payments

      @payments = @contract.contract_payments.by_due_date
      @documents = @contract.contract_documents.recent
      @rentals = @contract.space_rentals.includes(:location, :location_space).order(:starts_at)
      @productions = [ @contract.production ].compact
      @ticketing = @contract.draft_ticketing
      @tech = @contract.draft_tech
    end

    def new
      @contract = Current.organization.contracts.build
    end

    def create
      @contract = Current.organization.contracts.build(contract_params)

      if @contract.save
        redirect_to contractor_contract_wizard_path(@contract), notice: "Contract draft created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @contract.update(contract_params)
        redirect_to manage_contract_path(@contract), notice: "Contract updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # Only allow destroying cancelled contracts
      unless @contract.status_cancelled?
        redirect_to manage_contract_path(@contract), alert: "Only cancelled contracts can be deleted."
        return
      end

      # Remove this contract's shows; only delete the production if nothing else uses it.
      detach_and_maybe_delete_production(@contract)

      @contract.destroy
      redirect_to manage_contracts_path, notice: "Contract and all associated data permanently deleted."
    end

    def activate
      if @contract.activate!
        redirect_to manage_contract_path(@contract), notice: "Contract activated. Productions and shows have been created."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not activate contract: #{@contract.errors.full_messages.join(', ')}"
      end
    end

    def complete
      if @contract.complete!
        redirect_to manage_contract_path(@contract), notice: "Contract marked as completed."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not complete contract."
      end
    end

    def reopen
      if @contract.reopen!
        redirect_to amend_bookings_manage_contract_path(@contract),
          notice: "Contract reopened. Add your new dates, then review to apply your changes."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not reopen this contract."
      end
    end

    def cancel
      # GET action - show cancellation page
      @shows = @contract.contract_shows.order(:date_and_time).to_a
      @pending_payments = @contract.contract_payments.where(status: "pending")
      @pending_total = @pending_payments.sum(:amount)
    end

    def process_cancel
      # POST action - actually cancel the contract
      settlement_type = params[:settlement_type] || "cancel_all"
      cancellation_fee = params[:cancellation_fee].to_f

      transaction_success = @contract.transaction do
        # Handle settlement
        case settlement_type
        when "pay_remaining"
          # Keep pending payments as is - they still need to be paid
        when "flat_fee"
          # Cancel existing pending payments and create a cancellation fee payment
          @contract.contract_payments.where(status: "pending").update_all(status: "cancelled")
          if cancellation_fee > 0
            @contract.contract_payments.create!(
              description: "Cancellation Fee",
              amount: cancellation_fee,
              direction: "incoming",
              due_date: Date.current + 7.days,
              status: "pending"
            )
          end
        when "cancel_all"
          # Cancel all pending payments
          @contract.contract_payments.where(status: "pending").update_all(status: "cancelled")
        end

        # Remove this contract's shows (leave a shared production intact).
        detach_and_maybe_delete_production(@contract)

        # Mark contract as cancelled
        @contract.update!(
          status: :cancelled,
          cancelled_at: Time.current
        )
      end

      if transaction_success
        redirect_to manage_contracts_path, notice: "Contract cancelled and events deleted."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not cancel contract."
      end
    end

    def update_projection
      unless @contract.revenue_share?
        redirect_to manage_contract_path(@contract), alert: "Revenue projections are only available for revenue share contracts."
        return
      end

      @contract.set_revenue_projection(
        ticket_price_low: params[:ticket_price_low],
        ticket_price_high: params[:ticket_price_high],
        tickets_sold_low: params[:tickets_sold_low],
        tickets_sold_high: params[:tickets_sold_high],
        notes: params[:notes]
      )

      redirect_to manage_contract_path(@contract), notice: "Revenue projection updated."
    end

    # ==================== AMEND CONTRACT FLOW ====================

    # Step 1: Amend Bookings
    def amend_bookings
      @locations = Current.organization.locations.includes(:location_spaces)
      @existing_rentals = @contract.space_rentals.includes(:location, :location_space).order(:starts_at)

      # Get amend_data from contract (stored in draft_data["amend"])
      @amend_data = @contract.amend_data
      @amend_data["booking_rules"] ||= {}
      @amend_data["new_bookings"] ||= []
      @amend_data["removed_rental_ids"] ||= []
      @production_name = @amend_data["production_name"] || @contract.production_name.presence || @contract.production&.name
    end

    def save_amend_bookings
      booking_mode = params[:booking_mode] || "single"

      Rails.logger.info "[AMEND] save_amend_bookings called"
      Rails.logger.info "[AMEND] booking_mode: #{booking_mode}"
      Rails.logger.info "[AMEND] booking_rules_json: #{params[:booking_rules_json]}"
      Rails.logger.info "[AMEND] removed_rental_ids: #{params[:removed_rental_ids]}"

      if params[:booking_rules_json].present?
        rules_array = JSON.parse(params[:booking_rules_json]) rescue []
        booking_rules = { "rules" => rules_array, "booking_mode" => booking_mode }
      else
        booking_rules = {}
      end

      Rails.logger.info "[AMEND] parsed booking_rules: #{booking_rules}"

      removed_rental_ids = params[:removed_rental_ids].present? ? JSON.parse(params[:removed_rental_ids]) : []

      # Generate new bookings from rules
      new_bookings = generate_bookings_from_rules(booking_rules)

      Rails.logger.info "[AMEND] generated new_bookings: #{new_bookings.count} bookings"
      Rails.logger.info "[AMEND] new_bookings sample: #{new_bookings.first(3)}"

      # Store in contract's amend_data (persisted to database)
      existing_amend = @contract.amend_data
      @contract.update_amend_data(existing_amend.merge(
        "booking_rules" => booking_rules,
        "new_bookings" => new_bookings,
        "removed_rental_ids" => removed_rental_ids,
        "production_name" => params[:production_name].to_s.strip
      ))

      Rails.logger.info "[AMEND] amend_data saved for contract #{@contract.id}"

      redirect_to amend_events_manage_contract_path(@contract)
    end

    # Step 2: Review Events (full list with changes)
    def amend_events
      @amend_data = @contract.amend_data
      @existing_rentals = @contract.space_rentals.includes(:location, :location_space).order(:starts_at)

      @new_bookings = @amend_data["new_bookings"] || []
      @removed_rental_ids = @amend_data["removed_rental_ids"] || []

      # Separate existing rentals into kept and removed
      @rentals_to_remove = @existing_rentals.select { |r| @removed_rental_ids.include?(r.id) }
      @remaining_rentals = @existing_rentals.reject { |r| @removed_rental_ids.include?(r.id) }

      @locations = Current.organization.locations.includes(:location_spaces)
      @locations_map = @locations.index_by(&:id)
      @spaces_map = @locations.flat_map(&:location_spaces).index_by(&:id)

      # Build a unified list of all events for display
      @all_events_after = build_unified_event_list(@remaining_rentals, @new_bookings, @locations_map, @spaces_map)
    end

    # Step 3: The deal — the same Financials editor as the create wizard (who
    # sells, settlement, the generated payment list, add-a-payment, how they may
    # pay us). Seeded from the contract's current config and payments (or the
    # staged edits if you've been here before), applied on Confirm.
    def amend_payments
      @amend_data = @contract.amend_data

      @existing_payment_structure = @amend_data["payment_structure"].presence || @contract.draft_payment_structure
      @existing_payment_config = @amend_data["payment_config"].presence || @contract.draft_payment_config
      @existing_payments = @amend_data["payments"].presence || @contract.draft_payments

      offline = Array(@existing_payment_config["accepted_payment_methods"]) - [ "online" ]
      @offline_payment_methods = offline.presence || @contract.offline_payment_methods

      # The per-event count reflects the schedule after this amendment's add/removes.
      @bookings = effective_amend_bookings
      @bookings_count = @bookings.count
    end

    def save_amend_payments
      payments_data = params[:payments].present? ? JSON.parse(params[:payments]) : []
      payment_structure = params[:payment_structure].presence || "flat_fee"
      payment_config = params[:payment_config].present? ? JSON.parse(params[:payment_config]) : {}

      # Who sells is its own question; settlement basis derives from the structure.
      who_sells = params[:who_sells_tickets].presence
      payment_config["who_sells_tickets"] = who_sells.in?(%w[org contractor]) ? who_sells : nil
      payment_config["settlement_basis"] = settlement_basis_for(payment_structure, payment_config)

      # How they may pay us — online always, plus whatever offline methods are ticked.
      offline = Array(params[:offline_payment_methods]) & Contract::OFFLINE_PAYMENT_METHODS
      payment_config["accepted_payment_methods"] = [ "online" ] + offline

      # Stamp every payment with the derived direction so the four cases can't
      # produce a wrong-way payment.
      direction = derived_settlement_direction(payment_structure, payment_config)
      payments_data = payments_data.map { |p| p["extra"] ? p : p.merge("direction" => direction) }

      existing_amend = @contract.amend_data
      @contract.update_amend_data(existing_amend.merge(
        "payment_structure" => payment_structure,
        "payment_config" => payment_config,
        "payments" => payments_data
      ))

      redirect_to amend_ticketing_tech_manage_contract_path(@contract)
    end

    # Step 4: Amend the production name, ticketing, and services. Ticketing is
    # plain config on draft_data; services are catalog line items that become
    # billable payments, reconciled on apply. Staged in amend_data.
    def amend_ticketing_tech
      @amend_data = @contract.amend_data
      @ticketing = @amend_data["ticketing"] || @contract.draft_ticketing
      @service_options = Current.organization.contract_service_options.ordered
      @existing_services = @amend_data["services"] || @contract.draft_services
    end

    def save_amend_ticketing_tech
      ticketing_data = params[:ticketing].present? ? (JSON.parse(params[:ticketing]) rescue {}) : {}

      services = Array(params[:services]&.values).filter_map do |row|
        name = row[:name].to_s.strip
        next if name.blank? || row[:include] != "1"

        quantity = row[:quantity].to_f
        quantity = 1 if quantity <= 0
        {
          "name" => name,
          "quantity" => quantity,
          "unit_price" => row[:unit_price].to_f,
          "unit" => row[:unit].presence || "flat",
          "direction" => row[:direction].presence || "incoming"
        }
      end

      existing_amend = @contract.amend_data
      @contract.update_amend_data(existing_amend.merge(
        "ticketing" => ticketing_data,
        "services" => services
      ))

      redirect_to amend_review_manage_contract_path(@contract)
    end

    # Step 4: Review Amendments
    def amend_review
      @amend_data = @contract.amend_data
      @new_bookings = @amend_data["new_bookings"] || []
      @removed_rental_ids = @amend_data["removed_rental_ids"] || []

      @existing_rentals = @contract.space_rentals.includes(:location, :location_space).order(:starts_at)
      @existing_payments = @contract.contract_payments.order(:due_date)

      @locations = Current.organization.locations.includes(:location_spaces)
      @locations_map = @locations.index_by(&:id)
      @spaces_map = @locations.flat_map(&:location_spaces).index_by(&:id)

      # Calculate summary
      @rentals_to_remove = @existing_rentals.select { |r| @removed_rental_ids.include?(r.id) }

      # Financials: the deal config and/or payment list changed. Staged only if
      # the user visited that step; compared against the contract's live values.
      @financials_changed =
        (@amend_data.key?("payment_structure") && @amend_data["payment_structure"] != @contract.draft_payment_structure) ||
        (@amend_data.key?("payment_config") && @amend_data["payment_config"] != @contract.draft_payment_config) ||
        (@amend_data.key?("payments") && @amend_data["payments"] != @contract.draft_payments)

      # Real scheduling conflicts the new events would create (same room, same
      # time) — surfaced for explicit acknowledgement before applying.
      @conflicts = detect_amend_conflicts(@new_bookings, @removed_rental_ids)

      # Ticketing & services: staged values (present only if the user visited that
      # step), compared against the contract's current values for the summary.
      @ticketing_changed = @amend_data.key?("ticketing") && @amend_data["ticketing"] != @contract.draft_ticketing
      @services_changed = @amend_data.key?("services") && @amend_data["services"] != @contract.draft_services
      @new_ticketing = @amend_data["ticketing"] if @ticketing_changed
      @new_services = @amend_data["services"] if @services_changed

      # Production name change (blank means "no change" — we never wipe the name).
      staged_name = @amend_data["production_name"].to_s.strip
      @production_name_changed = staged_name.present? && staged_name != @contract.production_name.to_s
      @new_production_name = staged_name if @production_name_changed

      @has_changes = @new_bookings.any? || @removed_rental_ids.any? || @financials_changed ||
                     @ticketing_changed || @services_changed || @production_name_changed
    end

    def apply_amendments
      @amend_data = @contract.amend_data
      new_bookings = @amend_data["new_bookings"] || []
      removed_rental_ids = @amend_data["removed_rental_ids"] || []

      staged_production_name = @amend_data["production_name"].to_s.strip

      success = @contract.transaction do
        # The deal config (who sells + settlement) — write it through before
        # reconciling payments so their derived direction is correct.
        @contract.update_draft_step(:payment_structure, @amend_data["payment_structure"]) if @amend_data.key?("payment_structure")
        @contract.update_draft_step(:payment_config, @amend_data["payment_config"]) if @amend_data.key?("payment_config")

        # Ticketing is plain config — write it straight through.
        @contract.update_draft_step(:ticketing, @amend_data["ticketing"]) if @amend_data.key?("ticketing")

        # Services are billable line items. Reconcile: drop the pending payments
        # for the old set, save the new set, and bill the new set. Paid service
        # payments are left alone.
        if @amend_data.key?("services")
          @contract.reconcile_service_payments!(@amend_data["services"])
        end

        # Rename the contract's production and propagate to the linked Production
        # record(s) so the contract and the show stay in sync.
        if staged_production_name.present? && staged_production_name != @contract.production_name.to_s
          @contract.update!(production_name: staged_production_name)
          @contract.production&.update!(name: staged_production_name)
        end

        # Remove rentals and their associated shows
        if removed_rental_ids.any?
          Show.where(space_rental_id: removed_rental_ids).destroy_all
          @contract.space_rentals.where(id: removed_rental_ids).destroy_all
        end

        # Find the production for this contract (needed to create shows)
        production = @contract.production
        prod_data = @contract.draft_data["production"] || {}
        event_type = prod_data["event_type"].presence || "show"

        # Add new bookings as space_rentals AND create corresponding shows
        new_bookings.each do |booking|
          starts_at = Time.zone.parse(booking["starts_at"])
          duration_hours = (booking["duration"] || 2).to_f
          ends_at = starts_at + duration_hours.hours

          rental = @contract.space_rentals.create!(
            location_id: booking["location_id"],
            location_space_id: booking["space_id"].presence,
            starts_at: starts_at,
            ends_at: ends_at,
            # The actual event may run at a different time within the slot.
            event_starts_at: booking["event_starts_at"].present? ? Time.zone.parse(booking["event_starts_at"]) : nil,
            event_ends_at: booking["event_ends_at"].present? ? Time.zone.parse(booking["event_ends_at"]) : nil,
            notes: booking["notes"],
            confirmed: true,
            allow_overlap: params[:force_overlap] == "1"
          )

          # Create a show for the new rental so it appears in Shows & Events. It
          # runs at the event time, not necessarily the whole booked slot.
          if production
            production.shows.create!(
              date_and_time: rental.effective_event_starts_at,
              duration_minutes: rental.effective_duration_minutes,
              location: rental.location,
              location_space: rental.location_space,
              space_rental: rental,
              event_type: event_type
            )
          end
        end

        # Reconcile the payment list from the Financials editor. Runs after shows
        # exist so per-event payments can re-link; paid payments are preserved.
        @contract.reconcile_amended_payments!(@amend_data["payments"]) if @amend_data.key?("payments")

        # Update contract dates if needed
        all_rentals = @contract.space_rentals.reload
        if all_rentals.any?
          min_date = all_rentals.minimum(:starts_at)&.to_date
          max_date = all_rentals.maximum(:ends_at)&.to_date
          @contract.update!(
            contract_start_date: [ @contract.contract_start_date, min_date ].compact.min,
            contract_end_date: [ @contract.contract_end_date, max_date ].compact.max
          )
        end

        true
      end

      # Clear amend data from contract
      @contract.clear_amend_data

      if success
        redirect_to manage_contract_path(@contract), notice: "Contract amended successfully."
      else
        redirect_to amend_review_manage_contract_path(@contract), alert: "Could not apply amendments."
      end
    end

    private

    # Remove a contract's own shows, and delete its production only when no other
    # contract still uses it and it has no remaining shows (productions are shared).
    def detach_and_maybe_delete_production(contract)
      candidate_productions = []

      # Remove the course RUNS this contract created — but only empty ones; never
      # delete a run people have paid for. The durable course production survives
      # if it still has other runs.
      contract.course_offerings.each do |offering|
        next if offering.course_registrations.confirmed.exists?
        candidate_productions << offering.production
        offering.destroy
      end
      candidate_productions << contract.production

      # Unlink any contract payments that reference these shows BEFORE destroying
      # them — contract_payments.show_id has a FK that blocks deleting a
      # referenced show. Payments can belong to other contracts, so we only drop
      # the show link, never the payment itself.
      show_ids = contract.contract_shows.pluck(:id)
      ContractPayment.where(show_id: show_ids).update_all(show_id: nil) if show_ids.any?
      contract.contract_shows.destroy_all

      # Delete any touched production that's now genuinely empty and unshared —
      # no other contracts, no remaining runs, no remaining shows.
      candidate_productions.compact.uniq.each do |production|
        next if production.contracts.where.not(id: contract.id).any?
        next if production.course_offerings.any?
        next if production.shows.reload.any?
        production.destroy
      end
    end

    # The bookings the Financials step's per-event count should reflect: the
    # rentals that survive this amendment plus any newly-added ones. Shaped like
    # draft bookings ({ "starts_at" => iso }) for the shared partial.
    def effective_amend_bookings
      amend = @contract.amend_data
      removed = amend["removed_rental_ids"] || []
      remaining = @contract.space_rentals.where.not(id: removed).order(:starts_at)
      remaining.map { |r| { "starts_at" => r.starts_at.iso8601 } } +
        (amend["new_bookings"] || []).map { |b| { "starts_at" => b["starts_at"] } }
    end

    # The real scheduling conflicts this amendment's new events would create: a
    # new booking in a specific room that overlaps (in time) an existing booking
    # in that same room, or another new booking in the batch. Entire-venue
    # bookings are never checked (matching SpaceRental's own rule), and rentals
    # being removed in this same amendment don't count. Returns a list shaped for
    # the review's conflict modal.
    def detect_amend_conflicts(new_bookings, removed_rental_ids)
      buffer = 1.minute

      pending = new_bookings.filter_map do |b|
        next if b["space_id"].blank?

        starts = (Time.zone.parse(b["starts_at"]) rescue nil)
        next unless starts

        ends = starts + (b["duration"] || 2).to_f.hours
        { space_id: b["space_id"].to_i, starts: starts, ends: ends }
      end

      pending.map do |nb|
        against = []

        SpaceRental.joins(:contract)
                   .where(location_space_id: nb[:space_id])
                   .where.not(id: removed_rental_ids)
                   .where.not(contracts: { status: "cancelled" })
                   .where("space_rentals.starts_at < ? AND space_rentals.ends_at > ?", nb[:ends] - buffer, nb[:starts] + buffer)
                   .includes(:contract).each do |rental|
          who = rental.contract_id == @contract.id ? "This contract" : (rental.contract.contractor_name.presence || "Another contract")
          against << { label: who, when: conflict_window(rental.starts_at, rental.ends_at) }
        end

        pending.each do |other|
          next if other.equal?(nb) || other[:space_id] != nb[:space_id]
          next unless other[:starts] < nb[:ends] - buffer && other[:ends] > nb[:starts] + buffer

          against << { label: "Another new event", when: conflict_window(other[:starts], other[:ends]) }
        end

        next if against.empty?

        space = @spaces_map[nb[:space_id]]
        {
          space_name: space&.name || "Room",
          location_name: space&.location&.name,
          when: conflict_window(nb[:starts], nb[:ends]),
          against: against
        }
      end.compact
    end

    def conflict_window(starts, ends)
      "#{starts.strftime('%b %-d, %-l:%M %p').strip} – #{ends.strftime('%-l:%M %p').strip}"
    end

    # Basis a structure/config settles on — mirrors the create wizard.
    def settlement_basis_for(structure, config)
      case structure
      when "revenue_share" then "revenue_share"
      when "flat_fee"
        config["flat_fee_direction"] == "ticket_revenue_minus_fee" ? "revenue_minus_fee" : "flat"
      else "flat"
      end
    end

    # The derived money direction for a staged deal, without mutating the live
    # contract — mirrors Contract#settlement_direction.
    def derived_settlement_direction(structure, config)
      case settlement_basis_for(structure, config)
      when "revenue_share"
        config["who_sells_tickets"] == "org" ? "outgoing" : "incoming"
      when "revenue_minus_fee"
        "outgoing"
      else
        dir = config["flat_fee_direction"]
        %w[incoming outgoing].include?(dir) ? dir : "incoming"
      end
    end

    # Booking generation helpers (borrowed from wizard)
    def generate_bookings_from_rules(rules)
      return [] if rules.blank?

      rules_array = if rules["rules"].is_a?(Array)
        rules["rules"]
      elsif rules["mode"].present?
        [ rules ]
      else
        []
      end

      all_bookings = []
      rules_array.each do |rule|
        all_bookings.concat(generate_bookings_from_single_rule(rule))
      end

      all_bookings.sort_by { |b| b["starts_at"].to_s }
    end

    def generate_bookings_from_single_rule(rule)
      return [] if rule.blank?

      bookings = []
      mode = rule["mode"]

      if mode == "single"
        return [] if rule["starts_at"].blank?

        # Parse through Time.zone to ensure correct timezone (datetime-local inputs
        # have no timezone info, so we must interpret them in the app's timezone)
        parsed_starts_at = Time.zone.parse(rule["starts_at"])

        booking = {
          "location_id" => rule["location_id"],
          "space_id" => rule["space_id"],
          "starts_at" => parsed_starts_at.iso8601,
          "duration" => rule["duration"] || "2",
          "notes" => rule["notes"]
        }

        # Include event_starts_at if different from rental start
        if rule["event_starts_at"].present?
          parsed_event_starts_at = Time.zone.parse(rule["event_starts_at"])
          booking["event_starts_at"] = parsed_event_starts_at.iso8601
        end

        # Include event_ends_at if different from rental end
        if rule["event_ends_at"].present?
          parsed_event_ends_at = Time.zone.parse(rule["event_ends_at"])
          booking["event_ends_at"] = parsed_event_ends_at.iso8601
        end

        bookings << booking
      elsif mode == "recurring"
        location_id = rule["location_id"]
        space_id = rule["space_id"]
        frequency = rule["frequency"] || "weekly"
        day_of_week = (rule["day_of_week"] || "5").to_i
        time = rule["time"] || "19:00"
        duration = rule["duration"] || "2"
        start_date = Date.parse(rule["start_date"]) rescue Date.current
        end_date = Date.parse(rule["end_date"]) rescue (start_date + 3.months)
        notes = rule["notes"]

        week_ordinal = (rule["week_ordinal"] || "1").to_i
        monthly_day_of_week = (rule["monthly_day_of_week"] || day_of_week).to_i

        current_date = start_date

        case frequency
        when "daily"
          # Start on start_date
        when "monthly_day"
          current_date = find_nth_weekday_of_month(start_date.year, start_date.month, monthly_day_of_week, week_ordinal)
          if current_date < start_date
            next_month = start_date.next_month
            current_date = find_nth_weekday_of_month(next_month.year, next_month.month, monthly_day_of_week, week_ordinal)
          end
        when "monthly_date"
          # Use start_date's day of month
        else
          until current_date.wday == day_of_week
            current_date += 1.day
          end
        end

        max_events = 52
        count = 0
        event_time = rule["event_time"] # Optional different time for actual event start
        event_end_time = rule["event_end_time"] # Optional different time for actual event end

        while current_date <= end_date && count < max_events
          # Use Time.zone.parse to respect Rails time zone settings
          starts_at = Time.zone.parse("#{current_date} #{time}")

          booking = {
            "location_id" => location_id,
            "space_id" => space_id,
            "starts_at" => starts_at.iso8601,
            "duration" => duration,
            "notes" => notes
          }

          # Add event_starts_at if event_time is specified
          if event_time.present?
            event_starts_at = Time.zone.parse("#{current_date} #{event_time}")
            booking["event_starts_at"] = event_starts_at.iso8601
          end

          # Add event_ends_at if event_end_time is specified
          if event_end_time.present?
            event_ends_at = Time.zone.parse("#{current_date} #{event_end_time}")
            booking["event_ends_at"] = event_ends_at.iso8601
          end

          bookings << booking

          count += 1

          case frequency
          when "daily"
            current_date += 1.day
          when "weekly"
            current_date += 1.week
          when "biweekly"
            current_date += 2.weeks
          when "monthly_day"
            next_month = current_date.next_month
            current_date = find_nth_weekday_of_month(next_month.year, next_month.month, monthly_day_of_week, week_ordinal)
          when "monthly_date"
            current_date = current_date.next_month
          end
        end
      end

      bookings
    end

    def find_nth_weekday_of_month(year, month, wday, ordinal)
      first_of_month = Date.new(year, month, 1)

      if ordinal == 5
        last_of_month = first_of_month.end_of_month
        target = last_of_month
        until target.wday == wday
          target -= 1.day
        end
        target
      else
        target = first_of_month
        until target.wday == wday
          target += 1.day
        end
        target += (ordinal - 1).weeks
        target
      end
    end

    def build_unified_event_list(remaining_rentals, new_bookings, locations_map, spaces_map)
      events = []

      # Add existing (kept) rentals. If the show runs at a different time within
      # the booked slot, surface that alternate window for display.
      remaining_rentals.each do |rental|
        events << {
          type: :existing,
          starts_at: rental.starts_at,
          ends_at: rental.ends_at,
          location_name: rental.location&.name,
          space_name: rental.location_space&.name,
          duration: ((rental.ends_at - rental.starts_at) / 1.hour).round(1),
          event_starts_at: rental.has_separate_event_time? ? rental.effective_event_starts_at : nil,
          event_ends_at: rental.has_separate_event_time? ? rental.effective_event_ends_at : nil
        }
      end

      # Add new bookings, carrying the alternate show time set on the bookings step.
      new_bookings.each do |booking|
        starts_at = Time.zone.parse(booking["starts_at"])
        location = locations_map[booking["location_id"].to_i]
        space = spaces_map[booking["space_id"].to_i]
        duration = booking["duration"].to_f
        event_starts_at = (Time.zone.parse(booking["event_starts_at"]) if booking["event_starts_at"].present?)
        event_ends_at = (Time.zone.parse(booking["event_ends_at"]) if booking["event_ends_at"].present?)

        events << {
          type: :new,
          starts_at: starts_at,
          ends_at: starts_at + duration.hours,
          location_name: location&.name,
          space_name: space&.name,
          duration: duration,
          event_starts_at: event_starts_at,
          event_ends_at: event_ends_at
        }
      end

      # Sort by date
      events.sort_by { |e| e[:starts_at] }
    end

    def set_contract
      @contract = Current.organization.contracts.find(params[:id])
    end

    def contract_params
      params.require(:contract).permit(
        :contractor_name, :contractor_email, :contractor_phone, :contractor_address,
        :contract_start_date, :contract_end_date, :notes, :terms
      )
    end
  end
end
