# frozen_string_literal: true

module Manage
  class CourseOfferingsController < Manage::ManageController
    before_action :load_course_offering, only: %i[
      show edit update open_registration close_registration
      search_instructor update_instructor invite_instructor
    ]

    def index
      @course_offerings = Current.organization.productions
        .courses
        .active
        .includes(:course_offerings)
        .flat_map(&:course_offerings)
        .sort_by(&:created_at)
        .reverse
    end

    def show
      @registrations = @course_offering.course_registrations
        .where.not(status: :cancelled)
        .includes(:person)
        .order(registered_at: :desc)
      @sessions = @course_offering.sessions
    end

    def edit
      @sessions = @course_offering.sessions.includes(:location)
      @instructor_person = @course_offering.instructor_person
    end

    def update
      tab = params[:tab].to_i

      if @course_offering.update(course_offering_params)
        redirect_to manage_edit_course_offering_path(@course_offering, tab: tab), notice: "Course offering updated."
      else
        @sessions = @course_offering.sessions.includes(:location)
        @instructor_person = @course_offering.instructor_person
        render :edit, status: :unprocessable_entity
      end
    end

    def search_instructor
      query = params[:q].to_s.strip
      if query.length < 2
        render partial: "manage/course_offering_wizard/instructor_search_results",
               locals: { org_people: [], global_people: [], query: query, show_invite: false }
        return
      end

      # Search within org people first
      org_people = Current.organization.people.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q)",
        q: "%#{query}%"
      ).limit(10).to_a

      # Search globally (exclude org people)
      org_person_ids = Current.organization.people.pluck(:id)
      global_people = Person.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q)",
        q: "%#{query}%"
      ).where.not(id: org_person_ids).limit(10).to_a

      # Show invite if query looks like an email with no exact match
      show_invite = query.include?("@") &&
        org_people.none? { |p| p.email&.downcase == query.downcase } &&
        global_people.none? { |p| p.email&.downcase == query.downcase }

      render partial: "manage/course_offering_wizard/instructor_search_results",
             locals: { org_people: org_people, global_people: global_people, query: query, show_invite: show_invite }
    end

    def update_instructor
      person_id = params[:instructor_person_id]
      bio = params[:instructor_bio]

      updates = {}
      if person_id.present?
        person = Person.find(person_id)
        updates[:instructor_person_id] = person.id
        updates[:instructor_name] = person.name
      else
        updates[:instructor_person_id] = nil
      end
      updates[:instructor_bio] = bio if bio

      if @course_offering.update(updates)
        # If an instructor person was set, assign them to the Instructor role on all sessions
        if person_id.present? && @course_offering.instructor_person.present?
          assign_instructor_to_sessions(@course_offering)
        end
        redirect_to manage_edit_course_offering_path(@course_offering, tab: 1), notice: "Instructor updated."
      else
        redirect_to manage_edit_course_offering_path(@course_offering, tab: 1), alert: "Failed to update instructor."
      end
    end

    def invite_instructor
      name = params[:name].to_s.strip
      email = params[:email].to_s.strip

      if name.blank? || email.blank?
        render json: { error: "Name and email are required" }, status: :unprocessable_entity
        return
      end

      # Check if a user with this email already exists
      existing_user = User.find_by(email_address: email)
      if existing_user&.person
        render json: {
          person_id: existing_user.person.id,
          name: existing_user.person.name,
          email: existing_user.person.email,
          initials: existing_user.person.initials,
          headshot_url: existing_user.person.safe_headshot_variant(:tile) ? url_for(existing_user.person.safe_headshot_variant(:tile)) : nil,
          message: "This person already has an account"
        }
        return
      end

      # Create person + user + send invitation
      person = Person.create!(
        name: name,
        email: email,
        created_by_org: Current.organization
      )

      user = User.create!(
        email_address: email,
        password: SecureRandom.hex(32)
      )
      person.update!(user: user)

      UserMailer.invitation_email(user, Current.organization).deliver_later

      render json: {
        person_id: person.id,
        name: person.name,
        email: person.email,
        initials: person.initials,
        headshot_url: nil,
        message: "Invitation sent to #{email}"
      }
    end

    def open_registration
      # Create/update Stripe product and prices
      begin
        CourseOfferingStripeService.new(@course_offering).ensure_stripe_resources!
        @course_offering.update!(status: :open)
        redirect_to manage_course_offering_path(@course_offering), notice: "Registration is now open."
      rescue CourseOfferingStripeService::StripeError => e
        redirect_to manage_course_offering_path(@course_offering),
                    alert: "Failed to set up payment processing: #{e.message}"
      end
    end

    def close_registration
      @course_offering.update!(status: :closed)
      redirect_to manage_course_offering_path(@course_offering), notice: "Registration has been closed."
    end

    private

    def load_course_offering
      @course_offering = CourseOffering.find(params[:id])
      # Verify it belongs to the current organization
      unless @course_offering.production.organization == Current.organization
        redirect_to manage_course_offerings_path, alert: "Course offering not found."
      end
    end

    def course_offering_params
      permitted = params.require(:course_offering).permit(
        :title, :subtitle, :description,
        :early_bird_deadline,
        :currency, :capacity, :opens_at, :closes_at,
        :instruction_text, :success_text,
        :instructor_bio
      )

      # Convert dollar amounts to cents
      if params[:course_offering][:price_dollars].present?
        permitted[:price_cents] = (params[:course_offering][:price_dollars].to_f * 100).round
      end

      if params[:course_offering][:early_bird_price_dollars].present?
        permitted[:early_bird_price_cents] = (params[:course_offering][:early_bird_price_dollars].to_f * 100).round
      elsif params[:course_offering].key?(:early_bird_price_dollars)
        # Explicitly cleared — set to nil
        permitted[:early_bird_price_cents] = nil
      end

      permitted
    end

    def assign_instructor_to_sessions(course_offering)
      person = course_offering.instructor_person
      production = course_offering.production
      role = production.roles.find_by(name: "Instructor")
      return unless person && role

      # Add to org if not already
      unless Current.organization.people.exists?(id: person.id)
        Current.organization.organization_memberships.find_or_create_by!(person: person) do |m|
          m.role = :member
        end
      end

      # Add to talent pool
      pool = production.talent_pool
      unless pool.talent_pool_memberships.exists?(member: person)
        pool.talent_pool_memberships.create!(member: person)
      end

      # Assign to all sessions
      production.shows.find_each do |show|
        ShowPersonRoleAssignment.find_or_create_by!(
          show: show,
          assignable: person,
          role: role
        )
      end
    end
  end
end
