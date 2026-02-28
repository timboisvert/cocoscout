# frozen_string_literal: true

module Manage
  class ContractWizardController < ManageController
    before_action :set_contract, except: %i[new create_draft]

    # Step 0: Start new contract
    def new
      @contract = Current.organization.contracts.build
    end

    def create_draft
      @contract = Current.organization.contracts.build(
        contractor_name: params[:contract][:contractor_name].presence || "New Contract",
        status: :draft,
        wizard_step: 1
      )

      if @contract.save
        redirect_to manage_contractor_contract_wizard_path(@contract)
      else
        render :new, status: :unprocessable_entity
      end
    end

    # Resume a draft contract at its last step
    def resume
      step = @contract.wizard_step || 1
      redirect_to wizard_step_path(step)
    end

    # Step 1: Contractor info
    def contractor
      @step = 1
    end

    def save_contractor
      if @contract.update(contractor_params.merge(wizard_step: [ 2, @contract.wizard_step ].max))
        redirect_to manage_bookings_contract_wizard_path(@contract)
      else
        @step = 1
        render :contractor, status: :unprocessable_entity
      end
    end

    # Step 2: Bookings (space/time reservations)
    def bookings
      @step = 2
      @locations = Current.organization.locations.includes(:location_spaces)
      @existing_rules = @contract.draft_booking_rules || {}
    end

    def save_bookings
      # Parse the booking rules from the form - now supports multiple rules
      booking_mode = params[:booking_mode] || "single"

      if params[:booking_rules_json].present?
        # New multi-rule format
        rules_array = JSON.parse(params[:booking_rules_json]) rescue []
        rules = { "rules" => rules_array, "booking_mode" => booking_mode }
      else
        # Legacy single-rule format for backward compatibility
        mode = params[:booking_mode]

        single_rule = if mode == "recurring"
          {
            "mode" => "recurring",
            "location_id" => params[:recurring_location],
            "space_id" => params[:recurring_space],
            "frequency" => params[:recurring_frequency],
            "day_of_week" => params[:recurring_day_of_week],
            "time" => params[:recurring_time],
            "duration" => params[:recurring_duration],
            "start_date" => params[:recurring_start_date],
            "event_count" => params[:recurring_event_count],
            "notes" => params[:recurring_notes]
          }
        else
          {
            "mode" => "single",
            "location_id" => params[:single_location],
            "space_id" => params[:single_space],
            "starts_at" => params[:single_starts_at],
            "duration" => params[:single_duration],
            "notes" => params[:single_notes]
          }
        end
        rules = { "rules" => [ single_rule ], "booking_mode" => booking_mode }
      end

      @contract.update_draft_step(:booking_rules, rules)
      @contract.update_column(:wizard_step, [ 3, @contract.wizard_step ].max)
      redirect_to manage_schedule_preview_contract_wizard_path(@contract)
    end

    # Step 3: Schedule Preview (generated from rules)
    def schedule_preview
      @step = 3
      @locations = Current.organization.locations.includes(:location_spaces)
      rules = @contract.draft_booking_rules || {}
      @generated_bookings = generate_bookings_from_rules(rules)

      # Build lookup maps for display
      @locations_map = @locations.index_by(&:id)
      @spaces_map = @locations.flat_map(&:location_spaces).index_by(&:id)
    end

    def save_schedule_preview
      # Generate and save the actual bookings from rules
      rules = @contract.draft_booking_rules || {}
      bookings = generate_bookings_from_rules(rules)
      @contract.update_draft_step(:bookings, bookings)
      @contract.update_column(:wizard_step, [ 4, @contract.wizard_step ].max)
      redirect_to manage_services_contract_wizard_path(@contract)
    end

    # Step 4: Services included
    def services
      @step = 4
      @existing_services = @contract.draft_services
    end

    def save_services
      services_data = params[:services].present? ? JSON.parse(params[:services]) : []
      @contract.update_draft_step(:services, services_data)
      @contract.update_column(:wizard_step, [ 5, @contract.wizard_step ].max)
      redirect_to manage_payments_contract_wizard_path(@contract)
    end

    # Step 5: Payment schedule
    def payments
      @step = 5
      @existing_payments = @contract.draft_payments
      @existing_payment_structure = @contract.draft_payment_structure
      @existing_payment_config = @contract.draft_payment_config
      @bookings = @contract.draft_bookings || []
      @bookings_count = @bookings.count
    end

    def save_payments
      payments_data = params[:payments].present? ? JSON.parse(params[:payments]) : []
      payment_structure = params[:payment_structure].presence || "flat_fee"
      payment_config = params[:payment_config].present? ? JSON.parse(params[:payment_config]) : {}

      @contract.update_draft_step(:payments, payments_data)
      @contract.update_draft_step(:payment_structure, payment_structure)
      @contract.update_draft_step(:payment_config, payment_config)

      # Auto-set contract dates from bookings
      if @contract.contract_start_date.blank? || @contract.contract_end_date.blank?
        booking_dates = @contract.draft_bookings.map { |b| Time.zone.parse(b["starts_at"])&.to_date }.compact
        if booking_dates.any?
          @contract.contract_start_date = booking_dates.min if @contract.contract_start_date.blank?
          @contract.contract_end_date = booking_dates.max if @contract.contract_end_date.blank?
          @contract.save!
        end
      end

      @contract.update_column(:wizard_step, [ 6, @contract.wizard_step ].max)
      redirect_to manage_documents_contract_wizard_path(@contract)
    end

    # Step 6: Document upload
    def documents
      @step = 6
      @documents = @contract.contract_documents.recent
    end

    def save_documents
      if params[:contract_document].present? && params[:contract_document][:file].present?
        doc = @contract.contract_documents.build(
          name: params[:contract_document][:name].presence || "Contract Document",
          document_type: "signed_contract"
        )
        doc.file.attach(params[:contract_document][:file])

        unless doc.save
          @step = 6
          @documents = @contract.contract_documents.recent
          flash.now[:alert] = doc.errors.full_messages.join(", ")
          render :documents, status: :unprocessable_entity
          return
        end
      end

      @contract.update_column(:wizard_step, [ 7, @contract.wizard_step ].max)
      redirect_to manage_review_contract_wizard_path(@contract)
    end

    def delete_document
      doc = @contract.contract_documents.find(params[:document_id])
      doc.destroy
      redirect_to manage_documents_contract_wizard_path(@contract), notice: "Document deleted."
    end

    # Step 7: Review and activate
    def review
      @step = 7
      @valid_for_activation = @contract.valid_for_activation?
      @validation_errors = @contract.errors.full_messages unless @valid_for_activation
    end

    def activate
      @contract.allow_overlap = params[:allow_overlap] == "1"

      if @contract.activate!
        redirect_to manage_contract_path(@contract), notice: "Contract activated successfully!"
      else
        @step = 7
        @valid_for_activation = false
        @validation_errors = @contract.errors.full_messages
        render :review, status: :unprocessable_entity
      end
    end

    def cancel
      @contract.destroy if @contract.status_draft?
      redirect_to manage_contracts_path, notice: "Contract draft discarded."
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end

    def contractor_params
      params.require(:contract).permit(
        :contractor_name, :production_name, :contractor_email, :contractor_phone, :contractor_address
      )
    end

    def wizard_step_path(step)
      case step
      when 1 then manage_contractor_contract_wizard_path(@contract)
      when 2 then manage_bookings_contract_wizard_path(@contract)
      when 3 then manage_schedule_preview_contract_wizard_path(@contract)
      when 4 then manage_services_contract_wizard_path(@contract)
      when 5 then manage_payments_contract_wizard_path(@contract)
      when 6 then manage_documents_contract_wizard_path(@contract)
      when 7 then manage_review_contract_wizard_path(@contract)
      else manage_contractor_contract_wizard_path(@contract)
      end
    end

    def generate_bookings_from_rules(rules)
      return [] if rules.blank?

      # Handle both new multi-rule format and legacy single-rule format
      rules_array = if rules["rules"].is_a?(Array)
        rules["rules"]
      elsif rules["mode"].present?
        [ rules ] # Legacy single rule
      else
        []
      end

      all_bookings = []

      rules_array.each do |rule|
        all_bookings.concat(generate_bookings_from_single_rule(rule))
      end

      # Sort all bookings by start time
      all_bookings.sort_by { |b| b["starts_at"].to_s }
    end

    def generate_bookings_from_single_rule(rule)
      return [] if rule.blank?

      bookings = []
      mode = rule["mode"]

      if mode == "single"
        # Single event - just one booking
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
        # Generate recurring bookings based on pattern
        location_id = rule["location_id"]
        space_id = rule["space_id"]
        frequency = rule["frequency"] || "weekly"
        day_of_week = (rule["day_of_week"] || "5").to_i
        time = rule["time"] || "19:00"
        duration = rule["duration"] || "2"
        start_date = Date.parse(rule["start_date"]) rescue Date.current
        end_date = Date.parse(rule["end_date"]) rescue (start_date + 3.months)
        notes = rule["notes"]

        # For monthly_day frequency, get the ordinal and day of week
        week_ordinal = (rule["week_ordinal"] || "1").to_i
        monthly_day_of_week = (rule["monthly_day_of_week"] || day_of_week).to_i

        # Find the first occurrence of the day of week on or after start_date
        current_date = start_date

        case frequency
        when "daily"
          # Start on start_date for daily
        when "monthly_day"
          # Find the Nth weekday of the current month
          current_date = find_nth_weekday_of_month(start_date.year, start_date.month, monthly_day_of_week, week_ordinal)
          # If that date is before start_date, go to next month
          if current_date < start_date
            next_month = start_date.next_month
            current_date = find_nth_weekday_of_month(next_month.year, next_month.month, monthly_day_of_week, week_ordinal)
          end
        when "monthly_date"
          # Use start_date's day of month each month
          # current_date stays as start_date
        else
          # weekly, biweekly - find the right day of week
          until current_date.wday == day_of_week
            current_date += 1.day
          end
        end

        # Generate bookings until end_date (with a safety limit of 52)
        max_events = 52
        count = 0
        event_time = rule["event_time"] # Optional different time for actual event start
        event_end_time = rule["event_end_time"] # Optional different time for actual event end

        while current_date <= end_date && count < max_events
          starts_at = DateTime.parse("#{current_date} #{time}")

          booking = {
            "location_id" => location_id,
            "space_id" => space_id,
            "starts_at" => starts_at.iso8601,
            "duration" => duration,
            "notes" => notes
          }

          # Add event_starts_at if event_time is specified
          if event_time.present?
            event_starts_at = DateTime.parse("#{current_date} #{event_time}")
            booking["event_starts_at"] = event_starts_at.iso8601
          end

          # Add event_ends_at if event_end_time is specified
          if event_end_time.present?
            event_ends_at = DateTime.parse("#{current_date} #{event_end_time}")
            booking["event_ends_at"] = event_ends_at.iso8601
          end

          bookings << booking

          count += 1

          # Advance to next occurrence
          case frequency
          when "daily"
            current_date += 1.day
          when "weekly"
            current_date += 1.week
          when "biweekly"
            current_date += 2.weeks
          when "monthly_day"
            # Same ordinal weekday next month (e.g., 2nd Friday)
            next_month = current_date.next_month
            current_date = find_nth_weekday_of_month(next_month.year, next_month.month, monthly_day_of_week, week_ordinal)
          when "monthly_date"
            # Same day of month
            current_date = current_date.next_month
          end
        end
      end

      bookings
    end

    # Helper to find the Nth weekday of a month (e.g., 2nd Friday)
    # week_ordinal: 1=first, 2=second, 3=third, 4=fourth, 5=last
    def find_nth_weekday_of_month(year, month, wday, ordinal)
      first_of_month = Date.new(year, month, 1)

      if ordinal == 5
        # "Last" - find the last occurrence
        last_of_month = first_of_month.end_of_month
        target = last_of_month
        until target.wday == wday
          target -= 1.day
        end
        target
      else
        # Find the first occurrence of the weekday
        target = first_of_month
        until target.wday == wday
          target += 1.day
        end
        # Add weeks to get to the Nth occurrence
        target += (ordinal - 1).weeks
        target
      end
    end
  end
end
