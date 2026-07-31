# frozen_string_literal: true

module Manage
  class ContractWizardController < ManageController
    before_action :set_contract, except: %i[new create_draft]

    # Step 1: Choose the contractor. When launched from a specific contractor's
    # page (?contractor_id=), skip the picker entirely and drop straight into the
    # "what's this contract for?" step with the draft already created.
    def new
      if params[:contractor_id].present?
        contractor = Current.organization.contractors.find_by(id: params[:contractor_id])
        if contractor
          @contract = build_draft_for(contractor)
          if @contract.persisted?
            redirect_to manage_production_contract_wizard_path(@contract)
            return
          end
        end
      end

      @contract = Current.organization.contracts.build
      @contractors = Current.organization.contractors.alphabetical
    end

    def create_draft
      contractor = Current.organization.contractors.find_by(id: params.dig(:contract, :contractor_id).presence)

      # Require a contractor to be selected
      unless contractor
        @contract = Current.organization.contracts.build
        @contractors = Current.organization.contractors.alphabetical
        flash.now[:alert] = "Please select a contractor or create a new one."
        render :new, status: :unprocessable_entity
        return
      end

      @contract = build_draft_for(contractor)

      if @contract.persisted?
        redirect_to manage_production_contract_wizard_path(@contract)
      else
        @contractors = Current.organization.contractors.alphabetical
        render :new, status: :unprocessable_entity
      end
    end

    # Step "About" (a): what this contract is FOR — its name, and whether it's a
    # brand-new production or an existing one. (Moved off the create screen so
    # picking a contractor is the only thing step 1 asks.)
    def production
      @step = 1
      @linkable_productions = linkable_productions
      @link_production_id = @contract.draft_data["link_production_id"]
    end

    def save_production
      linked = linkable_productions.find_by(id: params[:link_production_id].presence)
      @contract.production_name = linked&.name.presence || params[:production_name].presence

      if linked
        @contract.draft_data = @contract.draft_data.merge("link_production_id" => linked.id)
      else
        # Switched back to "new production" — drop any prior link.
        @contract.draft_data = @contract.draft_data.except("link_production_id")
      end
      @contract.save!

      redirect_to manage_signing_contract_wizard_path(@contract)
    end

    # Step "About" (b): how this contract gets signed — CocoScout e-signature, or
    # the classic "already signed / I'll upload it" offline path. Stored on the
    # contract so the rest of the flow (and rollout of in-flight contracts) can key
    # off it; defaults to :offline so nothing changes unless e-sign is chosen.
    def signing
      @step = 1
    end

    def save_signing
      mode = params[:signing_mode] == "esign" ? "esign" : "offline"
      @contract.signing_mode = mode
      @contract.draft_data = @contract.draft_data.merge("signing_chosen" => true)
      @contract.save!
      redirect_to manage_bookings_contract_wizard_path(@contract)
    end

    # Resume a draft contract at its last step. The two "About" micro-steps come
    # before any wizard_step is banked, so send a still-nameless draft back there.
    def resume
      # Once it's been sent (or signed), the wizard is done — the contract page is
      # where you track and manage it.
      if @contract.signing_out_for_signature? || @contract.signing_executed?
        redirect_to manage_contract_path(@contract)
        return
      end

      if @contract.production_name.blank?
        redirect_to manage_production_contract_wizard_path(@contract)
        return
      end

      step = @contract.wizard_step || 2
      step = 2 if step < 2
      redirect_to wizard_step_path(step)
    end

    # Step 1: Contractor info (deprecated - redirect to bookings)
    def contractor
      # Contractor is now selected at contract creation, skip to bookings
      redirect_to manage_bookings_contract_wizard_path(@contract)
    end

    def save_contractor
      # Redirect to bookings since this step is deprecated
      redirect_to manage_bookings_contract_wizard_path(@contract)
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
      redirect_to manage_payments_contract_wizard_path(@contract)
    end

    # Step 5: Ticketing — only reached when WE sell the tickets.
    def ticketing
      @step = 5
      @existing_ticketing = @contract.draft_ticketing
    end

    def save_ticketing
      ticketing_data = params[:ticketing].present? ? JSON.parse(params[:ticketing]) : {}
      @contract.update_draft_step(:ticketing, ticketing_data)
      @contract.update_column(:wizard_step, [ 6, @contract.wizard_step ].max)
      redirect_to manage_tech_contract_wizard_path(@contract)
    end

    # Step 6: Services (optional) — draw from the org catalog, override price/qty.
    def tech
      @step = 6
      @service_options = Current.organization.contract_service_options.ordered
      @existing_services = @contract.draft_services
    end

    def save_tech
      # Collect the chosen service line items into draft_data["services"].
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

      @contract.update_draft_step(:services, services)

      # E-sign contracts generate their signed PDF — they never upload one, so
      # skip the Documents step and go straight to Review & Send.
      if @contract.signing_mode_esign?
        @contract.update_column(:wizard_step, [ 8, @contract.wizard_step ].max)
        redirect_to manage_review_contract_wizard_path(@contract)
      else
        @contract.update_column(:wizard_step, [ 7, @contract.wizard_step ].max)
        redirect_to manage_documents_contract_wizard_path(@contract)
      end
    end

    # Step 4: Financials — who sells the tickets, and how the deal settles.
    def payments
      @step = 4
      @existing_payments = @contract.draft_payments
      @existing_payment_structure = @contract.draft_payment_structure
      @existing_payment_config = @contract.draft_payment_config
      @offline_payment_methods = @contract.offline_payment_methods
      @bookings = @contract.draft_bookings || []
      @bookings_count = @bookings.count
    end

    def save_payments
      payments_data = params[:payments].present? ? JSON.parse(params[:payments]) : []
      payment_structure = params[:payment_structure].presence || "flat_fee"
      payment_config = params[:payment_config].present? ? JSON.parse(params[:payment_config]) : {}

      # Who sells the tickets is its own question, independent of how the deal
      # settles — we might sell the tickets on a deal that's a flat rental.
      who_sells = params[:who_sells_tickets].presence
      payment_config["who_sells_tickets"] = who_sells.in?(%w[org contractor]) ? who_sells : nil
      payment_config["settlement_basis"] = settlement_basis_for(payment_structure, payment_config)

      # How they may pay us. Online is always allowed; the offline methods are
      # whatever this deal ticks, starting from the org's default.
      offline = Array(params[:offline_payment_methods]) & Contract::OFFLINE_PAYMENT_METHODS
      payment_config["accepted_payment_methods"] = [ "online" ] + offline

      @contract.update_draft_step(:payment_structure, payment_structure)
      @contract.update_draft_step(:payment_config, payment_config)

      # Stamp every deal-generated payment with the derived direction, so
      # client-side generation can never produce the wrong direction for the four
      # cases. By-hand extras keep the direction chosen in the add-payment modal.
      direction = @contract.settlement_direction
      payments_data = payments_data.map { |p| p["extra"] ? p : p.merge("direction" => direction) }
      @contract.update_draft_step(:payments, payments_data)

      # Auto-set contract dates from bookings
      if @contract.contract_start_date.blank? || @contract.contract_end_date.blank?
        booking_dates = @contract.draft_bookings.map { |b| Time.zone.parse(b["starts_at"])&.to_date }.compact
        if booking_dates.any?
          @contract.contract_start_date = booking_dates.min if @contract.contract_start_date.blank?
          @contract.contract_end_date = booking_dates.max if @contract.contract_end_date.blank?
          @contract.save!
        end
      end

      # Ticketing is its own step, and only when we're the ones selling.
      @contract.update_column(:wizard_step, [ 5, @contract.wizard_step ].max)
      if @contract.org_sells_tickets?
        redirect_to manage_ticketing_contract_wizard_path(@contract)
      else
        redirect_to manage_tech_contract_wizard_path(@contract)
      end
    end

    # Step 7: Document upload (offline contracts only — e-sign generates its PDF).
    def documents
      return redirect_to manage_review_contract_wizard_path(@contract) if @contract.signing_mode_esign?

      @step = 7
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
          @step = 7
          @documents = @contract.contract_documents.recent
          flash.now[:alert] = doc.errors.full_messages.join(", ")
          render :documents, status: :unprocessable_entity
          return
        end
      end

      @contract.update_column(:wizard_step, [ 8, @contract.wizard_step ].max)
      redirect_to manage_review_contract_wizard_path(@contract)
    end

    def delete_document
      doc = @contract.contract_documents.find(params[:document_id])
      doc.destroy
      redirect_to manage_documents_contract_wizard_path(@contract), notice: "Document deleted."
    end

    # Step 8: Review the DATA. Offline contracts activate here; e-sign contracts
    # confirm the data is right, then continue into Prepare → Sign → Send.
    def review
      @step = 8
      @valid_for_activation = @contract.valid_for_activation?
      @validation_errors = @contract.errors.full_messages unless @valid_for_activation
      @conflicts = contract_conflicts
    end

    # E-sign proceed from Review → Prepare. We re-check for booking conflicts at
    # submit time (the page may have sat open while the calendar changed). If a
    # conflict now exists and the producer hasn't chosen to schedule anyway, we
    # bounce back to Review with the conflict bar. Otherwise we persist their
    # override decision (the rentals aren't created until signing) and continue.
    def save_review
      return redirect_to manage_review_contract_wizard_path(@contract) unless @contract.signing_mode_esign?

      @conflicts = contract_conflicts
      override = params[:allow_overlap] == "1"

      if @conflicts.any? && !override
        @step = 8
        @valid_for_activation = @contract.valid_for_activation?
        @validation_errors = @contract.errors.full_messages unless @valid_for_activation
        flash.now[:alert] = "There's a scheduling conflict — choose how to handle it before continuing."
        render :review, status: :unprocessable_entity
        return
      end

      persist_overlap_override(override)
      redirect_to manage_prepare_contract_wizard_path(@contract)
    end

    # Step 9: Prepare — pick the template and preview the fully rendered contract,
    # then lock it in. (?template_id= re-previews a different template.)
    def prepare
      return redirect_to manage_review_contract_wizard_path(@contract) unless @contract.signing_mode_esign?

      @step = 9
      @contract.update_column(:wizard_step, [ 9, @contract.wizard_step ].max)
      @active_templates = @contract.organization.contract_templates.active.order(:name)
      @selected_template = @active_templates.find { |t| t.id == params[:template_id].to_i } ||
                           @contract.contract_template || @active_templates.first
      @rendered_document = @selected_template ? @contract.render_document_for(@selected_template) : nil
    end

    def save_prepare
      template = @contract.organization.contract_templates.active.find_by(id: params[:contract_template_id])
      unless template
        redirect_to manage_prepare_contract_wizard_path(@contract), alert: "Choose a contract template."
        return
      end

      @contract.prepare_for_signature!(template: template)
      @contract.update_column(:wizard_step, [ 10, @contract.wizard_step ].max)
      redirect_to manage_sign_contract_wizard_path(@contract)
    end

    # Step 10: Sign — the org's own deliberate signature over the locked document.
    def sign
      return redirect_to manage_review_contract_wizard_path(@contract) unless @contract.signing_mode_esign?
      return redirect_to manage_prepare_contract_wizard_path(@contract) if @contract.contract_template.nil?

      @step = 10
      @contract.update_column(:wizard_step, [ 10, @contract.wizard_step ].max)
      @rendered_document = @contract.render_signable_document
    end

    def save_sign
      signer_name = params[:signer_name].to_s.strip

      if signer_name.blank? || params[:agree] != "1"
        @step = 10
        @rendered_document = @contract.render_signable_document
        flash.now[:alert] = "Type your name and confirm to sign."
        render :sign, status: :unprocessable_entity
        return
      end

      @contract.sign_by_org!(signer_name: signer_name, signed_by: Current.user, request: request)
      @contract.update_column(:wizard_step, [ 11, @contract.wizard_step ].max)
      redirect_to manage_send_contract_wizard_path(@contract)
    end

    # Step 11: Send — review what's going out, then send it for signature.
    def send_step
      return redirect_to manage_review_contract_wizard_path(@contract) unless @contract.signing_mode_esign?
      return redirect_to manage_sign_contract_wizard_path(@contract) unless @contract.organization_signature

      @step = 11
      @contract.update_column(:wizard_step, [ 11, @contract.wizard_step ].max)
      @signer_person = @contract.signer_person_record
      render :send # action is send_step (send is reserved), but the view is send.html.erb
    end

    # Attach a CocoScout user to the contract's contractor from the send step —
    # link an existing person (person_id) or invite one by email. Creates the
    # Contractor record if the contract only had free-text contractor details.
    def link_signer
      contractor = @contract.contractor ||
        Current.organization.contractors.create!(name: @contract.contractor_name.presence || "Contractor",
                                                 email: @contract.contractor_email)

      person =
        if params[:person_id].present?
          Person.find_by(id: params[:person_id])
        elsif params[:invite_email].present?
          email = params[:invite_email].to_s.strip.downcase
          name = params[:invite_name].to_s.strip.presence || email.split("@").first
          Person.where("LOWER(email) = ?", email).first || Person.create!(name: name, email: email)
        end

      if person
        Current.organization.people << person unless Current.organization.people.include?(person)
        contractor.update!(person: person)
        @contract.update!(contractor: contractor, contractor_email: person.email.presence || @contract.contractor_email,
                          contractor_name: @contract.contractor_name.presence || person.name)
        redirect_to manage_send_contract_wizard_path(@contract), notice: "#{person.name} is attached — you can send now."
      else
        redirect_to manage_send_contract_wizard_path(@contract), alert: "Pick a person or enter an email to invite."
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to manage_send_contract_wizard_path(@contract), alert: "Couldn't attach that person: #{e.record.errors.full_messages.to_sentence.presence || e.message}"
    end

    def save_send
      unless @contract.signer_person_record
        redirect_to manage_send_contract_wizard_path(@contract),
          alert: "Attach a CocoScout user before sending — search for them or invite them by email."
        return
      end

      if @contract.send_for_signature!
        # Link the contractor to their Person now (idempotent) so a member sees the
        # contract in My Contracts right away, not only once the async job runs.
        @contract.contractor&.ensure_person!
        # Notify the counterparty (email + in-app message) off the request thread.
        ContractSignatureRequestJob.perform_later(
          @contract.id,
          sign_contract_url(token: @contract.signing_token),
          Current.user&.id
        )
        redirect_to manage_contract_path(@contract),
                    notice: "Contract sent to #{@contract.contractor_name} for signature."
      else
        redirect_to manage_send_contract_wizard_path(@contract), alert: "This contract can't be sent yet."
      end
    end

    def activate
      @contract.allow_overlap = params[:allow_overlap] == "1"

      if @contract.activate!
        redirect_to manage_contract_path(@contract), notice: "Contract activated successfully!"
      else
        @step = 8
        @valid_for_activation = false
        @validation_errors = @contract.errors.full_messages
        # Re-detect conflicts so the bar (and its calendar/choices) reappears if
        # the clash showed up between page load and submit.
        @conflicts = contract_conflicts
        render :review, status: :unprocessable_entity
      end
    end

    def cancel
      @contract.destroy if @contract.status_draft?
      redirect_to manage_contracts_path, notice: "Contract draft discarded."
    end

    private

    # Derive the v2 settlement basis from the wizard's payment structure/config.
    def settlement_basis_for(structure, config)
      case structure
      when "revenue_share" then "revenue_share"
      when "flat_fee"
        config["flat_fee_direction"] == "ticket_revenue_minus_fee" ? "revenue_minus_fee" : "flat"
      else "flat"
      end
    end

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end

    # Proactive scheduling-conflict detection for the review step.
    def contract_conflicts
      @contract_conflicts ||= ContractBookingConflicts.new(@contract)
    end

    # Remember whether the producer chose to schedule over a conflict, so the
    # decision survives to activation/signing (where the rentals are created).
    def persist_overlap_override(override)
      @contract.update_column(:draft_data, @contract.draft_data.merge("allow_overlap" => override))
    end

    # Persist a fresh draft seeded with the contractor's snapshot. Used both by the
    # normal create flow and the skip-the-picker path from a contractor's page.
    # Production name + signing mode are chosen in the next two "About" steps.
    def build_draft_for(contractor)
      Current.organization.contracts.create(
        contractor_id: contractor.id,
        contractor_name: contractor.name,
        contractor_email: contractor.email,
        contractor_phone: contractor.phone,
        contractor_address: contractor.address,
        status: :draft,
        wizard_step: 2
      )
    end

    # Active productions not already tied to a contract — candidates a new contract
    # can attach to instead of creating a duplicate production.
    # Active productions a new contract can attach to instead of creating a
    # duplicate. Productions that already carry a contract ARE included — a
    # production can be the subject of several contracts over time (e.g. a new
    # contract extending the same show with the same or a different contractor).
    def linkable_productions
      Current.organization.productions.active.order(:name)
    end

    def contractor_params
      permitted = params.require(:contract).permit(
        :contractor_id, :contractor_name, :production_name, :contractor_email, :contractor_phone, :contractor_address
      )

      # If contractor_id is provided, sync the contractor info
      if permitted[:contractor_id].present?
        contractor = Current.organization.contractors.find_by(id: permitted[:contractor_id])
        if contractor
          permitted[:contractor_name] = contractor.name if permitted[:contractor_name].blank?
          permitted[:contractor_email] ||= contractor.email
          permitted[:contractor_phone] ||= contractor.phone
          permitted[:contractor_address] ||= contractor.address
        end
      end

      permitted
    end

    def wizard_step_path(step)
      case step
      when 1, 2 then manage_bookings_contract_wizard_path(@contract)
      when 3 then manage_schedule_preview_contract_wizard_path(@contract)
      when 4 then manage_payments_contract_wizard_path(@contract)   # Financials
      when 5 then manage_ticketing_contract_wizard_path(@contract)  # only when we sell
      when 6 then manage_tech_contract_wizard_path(@contract)       # Services
      when 7 then manage_documents_contract_wizard_path(@contract)
      when 8 then manage_review_contract_wizard_path(@contract)
      when 9 then manage_prepare_contract_wizard_path(@contract)
      when 10 then manage_sign_contract_wizard_path(@contract)
      when 11 then manage_send_contract_wizard_path(@contract)
      else manage_bookings_contract_wizard_path(@contract)
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
          "notes" => rule["notes"],
          "event_type" => rule["event_type"] || "show"
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
          # Use Time.zone.parse to ensure correct timezone (not UTC)
          starts_at = Time.zone.parse("#{current_date} #{time}")

          booking = {
            "location_id" => location_id,
            "space_id" => space_id,
            "starts_at" => starts_at.iso8601,
            "duration" => duration,
            "notes" => notes,
            "event_type" => rule["event_type"] || "show"
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
