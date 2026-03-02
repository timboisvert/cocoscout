# frozen_string_literal: true

module Manage
  class CourseOfferingWizardController < ManageController
    before_action :load_wizard_state

    # Step 1: Course basics (title, description)
    def basics
      @step = 1
    end

    def save_basics
      @wizard_state[:title] = params[:title].presence
      @wizard_state[:subtitle] = params[:subtitle].presence
      @wizard_state[:description] = params[:description].presence

      unless @wizard_state[:title].present?
        @step = 1
        flash.now[:alert] = "Please enter a course title."
        render :basics, status: :unprocessable_entity
        return
      end

      save_wizard_state
      redirect_to manage_course_wizard_schedule_path
    end

    # Step 2: Schedule (sessions & optional contract link)
    def schedule
      redirect_to manage_course_wizard_basics_path unless @wizard_state[:title].present?
      @step = 2
      @contracts = Current.organization.contracts.status_active.order(:contractor_name)
    end

    def save_schedule
      @wizard_state[:contract_id] = params[:contract_id].presence&.to_i
      @wizard_state[:schedule_mode] = params[:schedule_mode].presence || "independent"

      if @wizard_state[:schedule_mode] == "contract" && @wizard_state[:contract_id].present?
        # Store selected space rental IDs from the contract
        selected_rental_ids = Array(params[:rental_ids]).map(&:to_i).reject(&:zero?)
        @wizard_state[:selected_rental_ids] = selected_rental_ids
        @wizard_state[:sessions] = nil # Clear manual sessions
      else
        @wizard_state[:contract_id] = nil
        @wizard_state[:selected_rental_ids] = nil
        # Store manually entered sessions
        sessions = []
        if params[:session_datetimes].present?
          params[:session_datetimes].each_with_index do |dt, i|
            next if dt.blank?
            sessions << {
              datetime: dt,
              name: params[:session_names]&.[](i).presence,
              duration: params[:session_durations]&.[](i).presence&.to_i
            }
          end
        end
        @wizard_state[:sessions] = sessions
      end

      save_wizard_state
      redirect_to manage_course_wizard_instructor_path
    end

    # Step 3: Instructor info
    def instructor
      redirect_to manage_course_wizard_basics_path unless @wizard_state[:title].present?
      @step = 3
    end

    def save_instructor
      @wizard_state[:instructor_name] = params[:instructor_name].presence
      @wizard_state[:instructor_bio] = params[:instructor_bio].presence

      save_wizard_state
      redirect_to manage_course_wizard_pricing_path
    end

    # Step 4: Pricing
    def pricing
      redirect_to manage_course_wizard_basics_path unless @wizard_state[:title].present?
      @step = 4
    end

    def save_pricing
      price_dollars = params[:price_dollars].to_s.strip
      if price_dollars.blank? || price_dollars.to_f <= 0
        @step = 4
        flash.now[:alert] = "Please enter a valid price."
        render :pricing, status: :unprocessable_entity
        return
      end

      @wizard_state[:price_cents] = (price_dollars.to_f * 100).round
      @wizard_state[:currency] = params[:currency].presence || "usd"

      early_bird_dollars = params[:early_bird_price_dollars].to_s.strip
      if early_bird_dollars.present? && early_bird_dollars.to_f > 0
        @wizard_state[:early_bird_price_cents] = (early_bird_dollars.to_f * 100).round
        @wizard_state[:early_bird_deadline] = params[:early_bird_deadline].presence
      else
        @wizard_state[:early_bird_price_cents] = nil
        @wizard_state[:early_bird_deadline] = nil
      end

      save_wizard_state
      redirect_to manage_course_wizard_details_path
    end

    # Step 5: Capacity & registration windows, page content
    def details
      redirect_to manage_course_wizard_basics_path unless @wizard_state[:title].present?
      @step = 5
    end

    def save_details
      @wizard_state[:capacity] = params[:capacity].presence&.to_i
      @wizard_state[:opens_at] = params[:opens_at].presence
      @wizard_state[:closes_at] = params[:closes_at].presence
      @wizard_state[:instruction_text] = params[:instruction_text].presence
      @wizard_state[:success_text] = params[:success_text].presence

      save_wizard_state
      redirect_to manage_course_wizard_review_path
    end

    # Step 6: Review
    def review
      redirect_to manage_course_wizard_basics_path unless @wizard_state[:title].present?
      redirect_to manage_course_wizard_pricing_path unless @wizard_state[:price_cents].present?
      @step = 6

      # Load contract for display if linked
      if @wizard_state[:contract_id].present?
        @contract = Current.organization.contracts.find_by(id: @wizard_state[:contract_id])
        if @contract && @wizard_state[:selected_rental_ids].present?
          @selected_rentals = @contract.space_rentals
            .where(id: @wizard_state[:selected_rental_ids])
            .order(:starts_at)
        end
      end
    end

    # Create the production + course offering + shows
    def create_offering
      contract = nil
      if @wizard_state[:contract_id].present?
        contract = Current.organization.contracts.find_by(id: @wizard_state[:contract_id])
      end

      ActiveRecord::Base.transaction do
        # Create a course production behind the scenes
        @production = Current.organization.productions.create!(
          name: @wizard_state[:title],
          production_type: :course,
          casting_source: :talent_pool,
          casting_setup_completed: true,
          contract: contract
        )

        # Create the course offering
        @offering = @production.course_offerings.create!(
          title: @wizard_state[:title],
          subtitle: @wizard_state[:subtitle],
          description: @wizard_state[:description],
          instructor_name: @wizard_state[:instructor_name],
          instructor_bio: @wizard_state[:instructor_bio],
          price_cents: @wizard_state[:price_cents],
          currency: @wizard_state[:currency] || "usd",
          early_bird_price_cents: @wizard_state[:early_bird_price_cents],
          early_bird_deadline: @wizard_state[:early_bird_deadline],
          capacity: @wizard_state[:capacity],
          opens_at: @wizard_state[:opens_at],
          closes_at: @wizard_state[:closes_at],
          instruction_text: @wizard_state[:instruction_text],
          success_text: @wizard_state[:success_text],
          contract: contract
        )

        # Create shows (sessions) for the course
        create_course_sessions!(contract)
      end

      clear_wizard_state
      redirect_to manage_course_offering_path(@offering), notice: "Course offering created successfully!"
    rescue ActiveRecord::RecordInvalid => e
      @step = 6
      flash.now[:alert] = "Something went wrong: #{e.message}"
      render :review, status: :unprocessable_entity
    end

    # Cancel wizard
    def cancel
      clear_wizard_state
      redirect_to manage_course_offerings_path, notice: "Course creation cancelled."
    end

    private

    def create_course_sessions!(contract)
      if @wizard_state[:schedule_mode] == "contract" && contract.present? && @wizard_state[:selected_rental_ids].present?
        # Create sessions from selected contract space rentals
        rentals = contract.space_rentals.where(id: @wizard_state[:selected_rental_ids]).order(:starts_at)
        rentals.each do |rental|
          duration_minutes = ((rental.ends_at - rental.starts_at) / 60).to_i
          @production.shows.create!(
            date_and_time: rental.event_starts_at || rental.starts_at,
            duration_minutes: duration_minutes,
            location: rental.location,
            location_space: rental.location_space,
            space_rental: rental,
            event_type: "class"
          )
        end
      elsif @wizard_state[:sessions].present?
        # Create sessions from manually entered dates
        @wizard_state[:sessions].each do |session|
          next if session[:datetime].blank? && session["datetime"].blank?
          dt = Time.zone.parse(session[:datetime] || session["datetime"])
          duration = (session[:duration] || session["duration"])&.to_i || 60
          @production.shows.create!(
            date_and_time: dt,
            duration_minutes: duration,
            name: session[:name] || session["name"],
            event_type: "class"
          )
        end
      end
    end

    def load_wizard_state
      @wizard_state = Rails.cache.read(wizard_cache_key) || {}
      @wizard_state = @wizard_state.with_indifferent_access
    end

    def save_wizard_state
      Rails.cache.write(wizard_cache_key, @wizard_state.to_h, expires_in: 24.hours)
    end

    def clear_wizard_state
      Rails.cache.delete(wizard_cache_key)
    end

    def wizard_cache_key
      "course_offering_wizard:#{Current.user.id}:#{Current.organization.id}"
    end
  end
end
