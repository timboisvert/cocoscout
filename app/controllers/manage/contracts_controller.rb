# frozen_string_literal: true

module Manage
  class ContractsController < ManageController
    before_action :set_contract, except: %i[index new create]

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

      # Late payments (overdue)
      @late_payments = ContractPayment
        .joins(:contract)
        .includes(:contract)
        .where(contracts: { organization_id: Current.organization.id, status: "active" })
        .where(status: "pending")
        .where("due_date < ?", Date.current)
        .order(:due_date)

      # Upcoming payments (not overdue, due within 7 days)
      @upcoming_payments = ContractPayment
        .joins(:contract)
        .includes(:contract)
        .where(contracts: { organization_id: Current.organization.id, status: "active" })
        .where(status: "pending")
        .where("due_date >= ?", Date.current)
        .where("due_date <= ?", 7.days.from_now)
        .order(:due_date)

      @has_payments = @late_payments.any? || @upcoming_payments.any?
    end

    def show
      # Draft contracts should be edited via the wizard
      if @contract.status_draft?
        redirect_to manage_contractor_contract_wizard_path(@contract) and return
      end

      @payments = @contract.contract_payments.by_due_date
      @documents = @contract.contract_documents.recent
      @rentals = @contract.space_rentals.includes(:location, :location_space).order(:starts_at)
      @productions = @contract.productions.includes(:shows)
      @services = @contract.draft_services
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

      # Delete associated productions and their shows
      @contract.productions.each do |production|
        production.shows.destroy_all
        production.destroy
      end

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

    def cancel
      # GET action - show cancellation page
      @shows = @contract.productions.flat_map(&:shows).sort_by(&:date_and_time)
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

        # Delete associated productions and their shows
        @contract.productions.destroy_all

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
        "removed_rental_ids" => removed_rental_ids
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

    # Step 3: Amend Payments
    def amend_payments
      @existing_payments = @contract.contract_payments.order(:due_date)
      @existing_rentals = @contract.space_rentals.includes(:location, :location_space).order(:starts_at)

      # Get amend data from contract
      @amend_data = @contract.amend_data

      Rails.logger.info "[AMEND] amend_payments - amend_data keys: #{@amend_data.keys}"
      Rails.logger.info "[AMEND] amend_payments - new_bookings count: #{(@amend_data["new_bookings"] || []).count}"

      @new_bookings = @amend_data["new_bookings"] || []
      @removed_rental_ids = @amend_data["removed_rental_ids"] || []

      # Calculate remaining rentals after removals
      @remaining_rentals = @existing_rentals.reject { |r| @removed_rental_ids.include?(r.id) }
      @total_events_after = @remaining_rentals.count + @new_bookings.count

      # Initialize payment changes
      @amend_data["new_payments"] ||= []
      @amend_data["removed_payment_ids"] ||= []

      @locations = Current.organization.locations.includes(:location_spaces)
      @locations_map = @locations.index_by(&:id)
      @spaces_map = @locations.flat_map(&:location_spaces).index_by(&:id)
    end

    def save_amend_payments
      new_payments = params[:new_payments].present? ? JSON.parse(params[:new_payments]) : []
      payment_structure = params[:payment_structure].presence || "custom"
      payment_config = params[:payment_config].present? ? JSON.parse(params[:payment_config]) : {}

      # Update contract's amend_data
      existing_amend = @contract.amend_data
      @contract.update_amend_data(existing_amend.merge(
        "new_payments" => new_payments,
        "payment_structure" => payment_structure,
        "payment_config" => payment_config
      ))

      redirect_to amend_review_manage_contract_path(@contract)
    end

    # Step 4: Review Amendments
    def amend_review
      @amend_data = @contract.amend_data
      @new_bookings = @amend_data["new_bookings"] || []
      @removed_rental_ids = @amend_data["removed_rental_ids"] || []
      @new_payments = @amend_data["new_payments"] || []
      @removed_payment_ids = @amend_data["removed_payment_ids"] || []

      @existing_rentals = @contract.space_rentals.includes(:location, :location_space).order(:starts_at)
      @existing_payments = @contract.contract_payments.order(:due_date)

      @locations = Current.organization.locations.includes(:location_spaces)
      @locations_map = @locations.index_by(&:id)
      @spaces_map = @locations.flat_map(&:location_spaces).index_by(&:id)

      # Calculate summary
      @rentals_to_remove = @existing_rentals.select { |r| @removed_rental_ids.include?(r.id) }
      @payments_to_remove = @existing_payments.select { |p| @removed_payment_ids.include?(p.id) }

      @has_changes = @new_bookings.any? || @removed_rental_ids.any? || @new_payments.any? || @removed_payment_ids.any?
    end

    def apply_amendments
      @amend_data = @contract.amend_data
      new_bookings = @amend_data["new_bookings"] || []
      removed_rental_ids = @amend_data["removed_rental_ids"] || []
      new_payments = @amend_data["new_payments"] || []
      removed_payment_ids = @amend_data["removed_payment_ids"] || []

      success = @contract.transaction do
        # Remove rentals and their associated shows
        if removed_rental_ids.any?
          Show.where(space_rental_id: removed_rental_ids).destroy_all
          @contract.space_rentals.where(id: removed_rental_ids).destroy_all
        end

        # Find the production for this contract (needed to create shows)
        production = @contract.productions.first
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
            notes: booking["notes"],
            confirmed: true
          )

          # Create a show for the new rental so it appears in Shows & Events
          if production
            production.shows.create!(
              date_and_time: rental.starts_at,
              duration_minutes: (duration_hours * 60).to_i,
              location: rental.location,
              location_space: rental.location_space,
              space_rental: rental,
              event_type: event_type
            )
          end
        end

        # Remove payments
        @contract.contract_payments.where(id: removed_payment_ids).destroy_all if removed_payment_ids.any?

        # Add new payments
        new_payments.each do |payment|
          @contract.contract_payments.create!(
            description: payment["description"],
            amount: payment["amount"].to_f,
            direction: payment["direction"] || "incoming",
            due_date: Date.parse(payment["due_date"]),
            notes: payment["notes"],
            status: "pending"
          )
        end

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

      # Add existing (kept) rentals
      remaining_rentals.each do |rental|
        events << {
          type: :existing,
          starts_at: rental.starts_at,
          ends_at: rental.ends_at,
          location_name: rental.location&.name,
          space_name: rental.location_space&.name,
          duration: ((rental.ends_at - rental.starts_at) / 1.hour).round(1)
        }
      end

      # Add new bookings
      new_bookings.each do |booking|
        starts_at = Time.zone.parse(booking["starts_at"])
        location = locations_map[booking["location_id"].to_i]
        space = spaces_map[booking["space_id"].to_i]
        duration = booking["duration"].to_f

        events << {
          type: :new,
          starts_at: starts_at,
          ends_at: starts_at + duration.hours,
          location_name: location&.name,
          space_name: space&.name,
          duration: duration
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
