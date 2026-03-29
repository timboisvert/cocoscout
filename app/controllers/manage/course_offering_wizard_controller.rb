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
      redirect_to manage_course_wizard_instructor_path
    end

    # Step 2: Instructor info
    def instructor
      redirect_to manage_course_wizard_basics_path unless @wizard_state[:title].present?
      @step = 2
      ids = Array(@wizard_state[:instructor_person_ids]).map(&:to_i).reject(&:zero?)
      @instructor_people = ids.any? ? Person.where(id: ids).index_by(&:id).values_at(*ids).compact : []
    end

    def save_instructor
      @wizard_state[:instructor_person_ids] = Array(params[:instructor_person_ids]).map(&:to_i).reject(&:zero?)
      @wizard_state[:instructor_on_team] = params[:instructor_on_team] == "1"

      # Save per-instructor bios
      @wizard_state[:instructor_bios] ||= {}
      if params[:instructor_bios].is_a?(ActionController::Parameters) || params[:instructor_bios].is_a?(Hash)
        params[:instructor_bios].each do |person_id, bio|
          @wizard_state[:instructor_bios][person_id.to_s] = bio.presence
        end
      end
      # Clean up bios for removed instructors
      active_ids = @wizard_state[:instructor_person_ids].map(&:to_s)
      @wizard_state[:instructor_bios].select! { |k, _| active_ids.include?(k) }

      # Handle per-instructor headshot uploads
      @wizard_state[:instructor_headshot_blob_ids] ||= {}
      if params[:instructor_headshots].is_a?(ActionController::Parameters) || params[:instructor_headshots].is_a?(Hash)
        params[:instructor_headshots].each do |person_id, file|
          next unless file.present? && file.respond_to?(:original_filename)
          blob = ActiveStorage::Blob.create_and_upload!(
            io: file,
            filename: file.original_filename,
            content_type: file.content_type
          )
          @wizard_state[:instructor_headshot_blob_ids][person_id.to_s] = blob.id
        end
      end
      @wizard_state[:instructor_headshot_blob_ids].select! { |k, _| active_ids.include?(k) }

      # Keep instructor_name in sync with selected people
      if @wizard_state[:instructor_person_ids].any?
        people = Person.where(id: @wizard_state[:instructor_person_ids])
        @wizard_state[:instructor_name] = people.pluck(:name).join(", ")
      else
        @wizard_state[:instructor_name] = nil
      end

      save_wizard_state
      redirect_to manage_course_wizard_schedule_path
    end

    # Step 3: Schedule (sessions & optional contract link)
    def schedule
      redirect_to manage_course_wizard_basics_path unless @wizard_state[:title].present?
      @step = 3
      @contracts = Current.organization.contracts.status_active.order(:contractor_name)
      @locations = Current.organization.locations.order(:name)
    end

    def save_schedule
      @wizard_state[:contract_id] = params[:contract_id].presence&.to_i
      @wizard_state[:schedule_mode] = params[:schedule_mode].presence || "independent"
      @wizard_state[:location_id] = params[:location_id].presence&.to_i
      @wizard_state[:is_online] = params[:is_online] == "1"

      if @wizard_state[:schedule_mode] == "contract" && @wizard_state[:contract_id].present?
        # Store selected show IDs from the contract's events
        selected_show_ids = Array(params[:show_ids]).map(&:to_i).reject(&:zero?)
        @wizard_state[:selected_show_ids] = selected_show_ids
        @wizard_state[:sessions] = nil # Clear manual sessions
      else
        @wizard_state[:contract_id] = nil
        @wizard_state[:selected_show_ids] = nil
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
      redirect_to manage_course_wizard_pricing_path
    end

    def search_instructor
      q = params[:q].to_s.strip

      if q.blank? || q.length < 2
        render partial: "manage/course_offering_wizard/instructor_search_results",
               locals: { org_people: [], global_people: [], query: q, show_invite: false }
        return
      end

      # Search within organization people
      org_people = Current.organization.people.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q)",
        q: "%#{q}%"
      ).limit(10).to_a

      # Search globally (people not in this org)
      org_person_ids = Current.organization.people.pluck(:id)
      global_people = Person.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q)",
        q: "%#{q}%"
      ).where.not(id: org_person_ids).limit(10).to_a

      # Show invite if query looks like an email with no exact match
      show_invite = q.include?("@") &&
        org_people.none? { |p| p.email&.downcase == q.downcase } &&
        global_people.none? { |p| p.email&.downcase == q.downcase }

      render partial: "manage/course_offering_wizard/instructor_search_results",
             locals: { org_people: org_people, global_people: global_people, query: q, show_invite: show_invite }
    end

    # Invite a new person as instructor (creates Person + User + sends invitation)
    def invite_instructor
      email = params[:email]&.strip&.downcase
      name = params[:name]&.strip

      if email.blank? || name.blank?
        render json: { success: false, error: "Name and email are required" }, status: :unprocessable_entity
        return
      end

      # Check if person with this email already exists
      existing_person = Person.find_by(email: email)

      if existing_person
        # Add to org if needed
        unless existing_person.organizations.include?(Current.organization)
          existing_person.organizations << Current.organization
        end

        @wizard_state[:instructor_person_ids] = (Array(@wizard_state[:instructor_person_ids]) + [existing_person.id]).uniq
        @wizard_state[:instructor_name] = Person.where(id: @wizard_state[:instructor_person_ids]).pluck(:name).join(", ")
        save_wizard_state

        render json: { success: true, person_id: existing_person.id, message: "#{existing_person.name} selected as instructor" }
      else
        # Create new person and user account
        person = Person.create!(name: name, email: email)
        person.organizations << Current.organization

        user = User.create!(
          email_address: email,
          password: User.generate_secure_password
        )
        person.update!(user: user)

        # Send invitation email
        invitation = PersonInvitation.create!(
          email: email,
          organization: Current.organization
        )
        Manage::PersonMailer.person_invitation(invitation).deliver_later

        @wizard_state[:instructor_person_ids] = (Array(@wizard_state[:instructor_person_ids]) + [person.id]).uniq
        @wizard_state[:instructor_name] = Person.where(id: @wizard_state[:instructor_person_ids]).pluck(:name).join(", ")
        save_wizard_state

        render json: {
          success: true,
          person_id: person.id,
          message: "Invitation sent to #{name}. They've been selected as instructor."
        }
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
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

      @wizard_state[:promo_code] = params[:promo_code].to_s.strip.presence

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
      @wizard_state[:listed_in_directory] = params[:listed_in_directory] == "1"

      save_wizard_state
      redirect_to manage_course_wizard_review_path
    end

    # Step 6: Review
    def review
      redirect_to(manage_course_wizard_basics_path) and return unless @wizard_state[:title].present?
      redirect_to(manage_course_wizard_pricing_path) and return unless @wizard_state[:price_cents].present?
      @step = 6

      # Load instructor people for display
      ids = Array(@wizard_state[:instructor_person_ids]).map(&:to_i).reject(&:zero?)
      @instructor_people = ids.any? ? Person.where(id: ids).index_by(&:id).values_at(*ids).compact : []

      # Load contract for display if linked
      if @wizard_state[:contract_id].present?
        @contract = Current.organization.contracts.find_by(id: @wizard_state[:contract_id])
        if @contract && @wizard_state[:selected_show_ids].present?
          @selected_shows = Show.joins(:production)
            .where(productions: { contract_id: @contract.id })
            .where(id: @wizard_state[:selected_show_ids])
            .order(:date_and_time)
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

        # Set up instructor people if selected
        instructor_person_ids = Array(@wizard_state[:instructor_person_ids]).map(&:to_i).reject(&:zero?)
        instructor_people = instructor_person_ids.any? ? Person.where(id: instructor_person_ids).to_a : []
        instructor_people.each do |instructor_person|
          # Ensure instructor is in the organization
          unless instructor_person.organizations.include?(Current.organization)
            instructor_person.organizations << Current.organization
          end

          # Add instructor to the production's talent pool
          talent_pool = @production.talent_pool || @production.create_talent_pool!
          unless talent_pool.people.exists?(instructor_person.id)
            talent_pool.people << instructor_person
          end
        end

        # Create the course offering
        @offering = @production.course_offerings.create!(
          title: @wizard_state[:title],
          subtitle: @wizard_state[:subtitle],
          description: @wizard_state[:description],
          instructor_name: @wizard_state[:instructor_name],
          instructor_person: instructor_people.first,
          price_cents: @wizard_state[:price_cents],
          currency: @wizard_state[:currency] || "usd",
          early_bird_price_cents: @wizard_state[:early_bird_price_cents],
          early_bird_deadline: @wizard_state[:early_bird_deadline],
          capacity: @wizard_state[:capacity],
          opens_at: @wizard_state[:opens_at],
          closes_at: @wizard_state[:closes_at],
          instruction_text: @wizard_state[:instruction_text],
          success_text: @wizard_state[:success_text],
          contract: contract,
          instructor_on_team: @wizard_state[:instructor_on_team] == true,
          listed_in_directory: @wizard_state[:listed_in_directory] != false
        )

        # Attach instructor headshot if uploaded during wizard (legacy, keep first instructor's)
        instructor_headshot_blob_ids = @wizard_state[:instructor_headshot_blob_ids] || {}
        if instructor_headshot_blob_ids.any?
          first_blob = ActiveStorage::Blob.find_by(id: instructor_headshot_blob_ids.values.first)
          @offering.instructor_headshot.attach(first_blob) if first_blob
        end

        # Redeem promo code if provided
        if @wizard_state[:promo_code].present?
          credit = FeatureCredit.find_by_normalized_code(@wizard_state[:promo_code])
          if credit&.redeemable? && credit.feature_type == "courses"
            redemption = credit.redeem!(
              organization: Current.organization,
              redeemable: @offering
            )
            @offering.update!(feature_credit_redemption: redemption)
          end
        end

        # Create shows (sessions) for the course
        create_course_sessions!(contract)

        # Create course_offering_instructors join records with per-instructor bio/headshot
        instructor_bios = @wizard_state[:instructor_bios] || {}
        instructor_headshot_blob_ids = @wizard_state[:instructor_headshot_blob_ids] || {}
        instructor_people.each_with_index do |instructor_person, position|
          coi = @offering.course_offering_instructors.create!(
            person: instructor_person,
            position: position,
            bio: instructor_bios[instructor_person.id.to_s]
          )
          blob_id = instructor_headshot_blob_ids[instructor_person.id.to_s]
          if blob_id.present?
            blob = ActiveStorage::Blob.find_by(id: blob_id)
            coi.headshot.attach(blob) if blob
          end
        end

        # Assign instructors to the Instructor role for all sessions
        instructor_role = @production.roles.find_by(name: "Instructor")
        if instructor_role
          instructor_people.each do |instructor_person|
            @production.shows.each do |show|
              ShowPersonRoleAssignment.find_or_create_by!(
                show: show,
                role: instructor_role,
                assignable: instructor_person
              )
            end
          end
        end

        # Add instructors to production team if requested
        if @offering.instructor_on_team
          instructor_people.each do |instructor_person|
            next unless instructor_person.user.present?

            ProductionPermission.find_or_create_by!(
              user: instructor_person.user,
              production: @production
            ) { |pp| pp.role = "manager" }

            ProductionNotificationSetting.find_or_create_by!(
              user: instructor_person.user,
              production: @production
            ) { |ns| ns.enabled = true }
            ProductionNotificationSetting.where(
              user: instructor_person.user,
              production: @production
            ).update_all(enabled: true)
          end
        end
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
      if @wizard_state[:schedule_mode] == "contract" && contract.present? && @wizard_state[:selected_show_ids].present?
        # Move selected shows from the contract's production to the course production
        shows = Show.joins(:production)
          .where(productions: { contract_id: contract.id })
          .where(id: @wizard_state[:selected_show_ids])
        shows.each do |show|
          show.update!(production: @production, event_type: "class")
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
            secondary_name: session[:name] || session["name"],
            event_type: "class",
            location_id: @wizard_state[:location_id],
            is_online: @wizard_state[:is_online] || false
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
