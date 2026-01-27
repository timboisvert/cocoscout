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
      if @contract.update(contractor_params.merge(wizard_step: [2, @contract.wizard_step].max))
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
      # Parse the booking rules from the form
      mode = params[:booking_mode]

      rules = if mode == "recurring"
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

      @contract.update_draft_step(:booking_rules, rules)
      @contract.update_column(:wizard_step, [3, @contract.wizard_step].max)
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
      @contract.update_column(:wizard_step, [4, @contract.wizard_step].max)
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
      @contract.update_column(:wizard_step, [5, @contract.wizard_step].max)
      redirect_to manage_payments_contract_wizard_path(@contract)
    end

    # Step 5: Payment schedule
    def payments
      @step = 5
      @existing_payments = @contract.draft_payments
    end

    def save_payments
      payments_data = params[:payments].present? ? JSON.parse(params[:payments]) : []
      @contract.update_draft_step(:payments, payments_data)
      @contract.update_column(:wizard_step, [6, @contract.wizard_step].max)
      redirect_to manage_terms_contract_wizard_path(@contract)
    end

    # Step 6: Terms and notes
    def terms
      @step = 6
    end

    def save_terms
      if @contract.update(terms_params.merge(wizard_step: [7, @contract.wizard_step].max))
        redirect_to manage_review_contract_wizard_path(@contract)
      else
        @step = 6
        render :terms, status: :unprocessable_entity
      end
    end

    # Step 7: Review and activate
    def review
      @step = 7
      @valid_for_activation = @contract.valid_for_activation?
      @validation_errors = @contract.errors.full_messages unless @valid_for_activation
    end

    def activate
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
        :contractor_name, :contractor_email, :contractor_phone, :contractor_address
      )
    end

    def terms_params
      params.require(:contract).permit(
        :contract_start_date, :contract_end_date, :terms, :notes
      )
    end

    def wizard_step_path(step)
      case step
      when 1 then manage_contractor_contract_wizard_path(@contract)
      when 2 then manage_bookings_contract_wizard_path(@contract)
      when 3 then manage_schedule_preview_contract_wizard_path(@contract)
      when 4 then manage_services_contract_wizard_path(@contract)
      when 5 then manage_payments_contract_wizard_path(@contract)
      when 6 then manage_terms_contract_wizard_path(@contract)
      when 7 then manage_review_contract_wizard_path(@contract)
      else manage_contractor_contract_wizard_path(@contract)
      end
    end

    def generate_bookings_from_rules(rules)
      return [] if rules.blank?

      bookings = []
      mode = rules["mode"]

      if mode == "single"
        # Single event - just one booking
        return [] if rules["starts_at"].blank?

        bookings << {
          "location_id" => rules["location_id"],
          "space_id" => rules["space_id"],
          "starts_at" => rules["starts_at"],
          "duration" => rules["duration"] || "2",
          "notes" => rules["notes"]
        }
      elsif mode == "recurring"
        # Generate recurring bookings based on pattern
        location_id = rules["location_id"]
        space_id = rules["space_id"]
        frequency = rules["frequency"] || "weekly"
        day_of_week = (rules["day_of_week"] || "5").to_i
        time = rules["time"] || "19:00"
        duration = rules["duration"] || "2"
        start_date = Date.parse(rules["start_date"]) rescue Date.current
        event_count = (rules["event_count"] || "8").to_i
        notes = rules["notes"]

        # Find the first occurrence of the day of week on or after start_date
        current_date = start_date
        until current_date.wday == day_of_week
          current_date += 1.day
        end

        # Generate bookings based on frequency
        count = 0
        while count < event_count
          starts_at = DateTime.parse("#{current_date} #{time}")

          bookings << {
            "location_id" => location_id,
            "space_id" => space_id,
            "starts_at" => starts_at.iso8601,
            "duration" => duration,
            "notes" => notes
          }

          count += 1

          # Advance to next occurrence
          case frequency
          when "weekly"
            current_date += 1.week
          when "biweekly"
            current_date += 2.weeks
          when "monthly"
            # Same day of week, next month (e.g., 2nd Friday)
            week_of_month = ((current_date.day - 1) / 7) + 1
            next_month = current_date.next_month.beginning_of_month

            # Find the same week/day combo in next month
            target_date = next_month
            until target_date.wday == day_of_week
              target_date += 1.day
            end
            target_date += (week_of_month - 1).weeks

            # If we went past the end of month, use last occurrence
            if target_date.month != next_month.month
              target_date -= 1.week
            end

            current_date = target_date
          end
        end
      end

      bookings
    end
  end
end
