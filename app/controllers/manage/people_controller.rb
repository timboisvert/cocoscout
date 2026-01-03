# frozen_string_literal: true

module Manage
  class PeopleController < Manage::ManageController
    before_action :set_person, only: %i[show update update_availability]
    before_action :ensure_user_is_global_manager, except: %i[show remove_from_organization]

    def show
      # Get all future shows for productions this person is a cast member of
      production_ids = TalentPool.joins(:talent_pool_memberships)
                                 .where(talent_pool_memberships: { member: @person })
                                 .pluck(:production_id).uniq
      @shows = Show.where(production_id: production_ids, canceled: false)
                   .where("date_and_time >= ?", Time.current)
                   .includes(event_linkage: :shows)
                   .order(:date_and_time)

      # Build a hash of availabilities: { show_id => show_availability }
      @availabilities = {}
      @person.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[availability.show_id] = availability
      end

      # Track edit mode
      @edit_mode = params[:edit] == "true"

      # Load email logs for this person (paginated, with search)
      # Scope to current organization to exclude system emails and cross-org emails
      email_logs_query = EmailLog.for_recipient_entity(@person).for_organization(Current.organization).recent
      if params[:search_messages].present?
        search_term = "%#{params[:search_messages]}%"
        email_logs_query = email_logs_query.where("subject LIKE ? OR body LIKE ?", search_term, search_term)
      end
      @email_logs_pagy, @email_logs = pagy(email_logs_query, limit: 10, page_param: :messages_page, page: params[:messages_page])
      @search_messages_query = params[:search_messages]
    end

    def new
      @person = Person.new
    end

    # AJAX endpoint to check if an email has existing profiles
    def check_email
      email = params[:email]&.strip&.downcase
      return render json: { profiles: [] } if email.blank?

      # Find all profiles with this email
      profiles = Person.where(email: email).includes(:user, :organizations)

      profiles_data = profiles.map do |person|
        {
          id: person.id,
          name: person.name,
          email: person.email,
          has_user: person.user.present?,
          already_in_org: person.organizations.include?(Current.organization)
        }
      end

      render json: { profiles: profiles_data }
    end

    def create
      email = person_params[:email]&.strip&.downcase

      # Check if specific profile IDs were selected
      selected_profile_ids = params[:selected_profile_ids]&.reject(&:blank?)&.map(&:to_i) || []

      if selected_profile_ids.any?
        # Inviting specific selected profiles
        invite_selected_profiles(selected_profile_ids)
      else
        # Check if a user with this email already exists (by login email)
        existing_user = User.find_by(email_address: email)

        if existing_user
          # User exists - invite their profile (don't auto-add, require acceptance)
          existing_person = existing_user.person
          if existing_person.organizations.include?(Current.organization)
            redirect_to [ :manage, existing_person ],
                        notice: "#{existing_person.name} is already a member of #{Current.organization.name}"
          else
            invite_single_profile(existing_person)
          end
        else
          # Check if any profiles exist with this email
          existing_profiles = Person.where(email: email)

          if existing_profiles.count > 1
            # Multiple profiles with same email - need user to select which ones
            @person = Person.new(person_params)
            @multiple_profiles = existing_profiles
            render :new, status: :unprocessable_entity
          elsif existing_profiles.count == 1
            # Single profile exists - use it
            existing_person = existing_profiles.first
            invite_single_profile(existing_person)
          else
            # No existing profiles - create new person and user
            create_new_person_and_invite
          end
        end
      end
    end

    private

    def invite_selected_profiles(profile_ids)
      profiles = Person.where(id: profile_ids, email: person_params[:email]&.downcase)
      invitation_subject = params[:person][:invitation_subject] || default_invitation_subject
      invitation_message = params[:person][:invitation_message] || default_invitation_message

      invited_names = []

      profiles.each do |person|
        # Note: We don't add the person to the organization here.
        # They will be added when they accept the invitation.

        # Create user if needed
        if person.user.nil?
          user = User.create!(
            email_address: person.email,
            password: SecureRandom.hex(16)
          )
          person.update!(user: user)
        end

        # Create and send invitation
        person_invitation = PersonInvitation.create!(
          email: person.email,
          organization: Current.organization
        )
        Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later

        invited_names << person.name
      end

      if invited_names.count == 1
        redirect_to [ :manage, profiles.first ], notice: "Invitation sent to #{invited_names.first}"
      else
        redirect_to manage_people_path, notice: "Invitations sent to #{invited_names.to_sentence}"
      end
    end

    def invite_single_profile(person)
      invitation_subject = params[:person][:invitation_subject] || default_invitation_subject
      invitation_message = params[:person][:invitation_message] || default_invitation_message

      # Note: We don't add the person to the organization here.
      # They will be added when they accept the invitation.

      if person.user.nil?
        user = User.create!(
          email_address: person.email,
          password: SecureRandom.hex(16)
        )
        person.update!(user: user)
      end

      person_invitation = PersonInvitation.create!(
        email: person.email,
        organization: Current.organization
      )
      Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later

      redirect_to [ :manage, person ],
                  notice: "User account created and invitation sent to #{person.name}"
    end

    def create_new_person_and_invite
      @person = Person.new(person_params)

      if @person.save
        # Note: We don't add the person to the organization here.
        # They will be added when they accept the invitation.

        user = User.create!(
          email_address: @person.email,
          password: SecureRandom.hex(16)
        )
        @person.update!(user: user)

        invitation_subject = params[:person][:invitation_subject] || default_invitation_subject
        invitation_message = params[:person][:invitation_message] || default_invitation_message

        person_invitation = PersonInvitation.create!(
          email: @person.email,
          organization: Current.organization
        )
        Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later

        redirect_to [ :manage, @person ], notice: "Person was successfully created and invitation sent"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def default_invitation_subject
      EmailTemplateService.render_subject("person_invitation", {
        organization_name: Current.organization.name
      })
    end

    def default_invitation_message
      EmailTemplateService.render_body("person_invitation", {
        organization_name: Current.organization.name,
        setup_url: "[setup link will be included]"
      })
    end

    public

    def update
      if @person.update(person_params)
        redirect_to [ :manage, @person ], notice: "Person was successfully updated", status: :see_other
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def update_availability
      # Update availabilities for each show
      updated_count = 0
      last_status = nil
      params.each do |key, value|
        next unless key.start_with?("availability_") && key != "availability"

        show_id = key.split("_").last.to_i
        next if show_id.zero?

        show = Show.find_by(id: show_id)
        next unless show

        availability = @person.show_availabilities.find_or_initialize_by(show: show)

        # Only update if the status has changed
        new_status = value
        current_status = if availability.available?
                           "available"
        elsif availability.unavailable?
                           "unavailable"
        end

        next unless new_status != current_status

        case new_status
        when "available"
          availability.available!
        when "unavailable"
          availability.unavailable!
        end

        availability.save
        updated_count += 1
        last_status = new_status
      end

      respond_to do |format|
        format.json do
          if updated_count.positive?
            render json: { status: last_status }
          else
            render json: { error: "No changes made" }, status: :unprocessable_entity
          end
        end
        format.html do
          if updated_count.positive?
            redirect_to manage_person_path(@person, tab: 2),
                        notice: "Availability updated for #{updated_count} #{'show'.pluralize(updated_count)}"
          else
            redirect_to manage_person_path(@person, tab: 2), alert: "No availability changes were made"
          end
        end
      end
    end

    def batch_invite
      emails_text = params[:emails].to_s
      email_lines = emails_text.split(/\r?\n/).map(&:strip).reject(&:blank?)

      invitation_subject = params[:invitation_subject] || default_invitation_subject
      invitation_message = params[:invitation_message] || default_invitation_message

      @invited = []
      @skipped = []
      @skipped_multiple_profiles = []
      @errors = []

      email_lines.each do |email|
        email = email.downcase

        # Validate email format
        unless email.match?(/\A[\w+\-.]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i)
          @errors << { email: email, reason: "Invalid email format" }
          next
        end

        # Check if multiple profiles have this email
        profiles_with_email = Person.where(email: email)
        if profiles_with_email.count > 1
          @skipped_multiple_profiles << { email: email, count: profiles_with_email.count }
          next
        end

        # Check if user already exists (by login email)
        existing_user = User.find_by(email_address: email)
        if existing_user
          existing_person = existing_user.person
          if existing_person.organizations.include?(Current.organization)
            @skipped << { email: email, name: existing_person.name, reason: "Already in organization" }
          else
            existing_person.organizations << Current.organization
            @invited << { email: email, name: existing_person.name, new_account: false }
          end
          next
        end

        # Check if exactly one person exists with this email
        existing_person = profiles_with_email.first

        if existing_person
          if existing_person.organizations.include?(Current.organization)
            @skipped << { email: email, name: existing_person.name, reason: "Already in organization" }
            next
          end

          # Person exists - add to org and create user if needed
          existing_person.organizations << Current.organization

          if existing_person.user.nil?
            user = User.create!(
              email_address: existing_person.email,
              password: SecureRandom.hex(16)
            )
            existing_person.update!(user: user)

            # Send invitation
            person_invitation = PersonInvitation.create!(
              email: existing_person.email,
              organization: Current.organization
            )
            Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later
          end

          @invited << { email: email, name: existing_person.name, new_account: existing_person.user.present? }
        else
          # Create new person and user
          name = email.split("@").first.gsub(/[._-]/, " ").titleize
          person = Person.new(name: name, email: email)

          if person.save
            person.organizations << Current.organization

            user = User.create!(
              email_address: person.email,
              password: SecureRandom.hex(16)
            )
            person.update!(user: user)

            person_invitation = PersonInvitation.create!(
              email: person.email,
              organization: Current.organization
            )
            Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later

            @invited << { email: email, name: person.name, new_account: true }
          else
            @errors << { email: email, reason: person.errors.full_messages.join(", ") }
          end
        end
      end

      @batch_results = true
      @person = Person.new  # For the form
      render :new
    end

    def add_to_cast
      @talent_pool = TalentPool.find(params[:talent_pool_id])
      @person = Current.organization.people.find(params[:person_id])
      @talent_pool.people << @person unless @talent_pool.people.include?(@person)
      render partial: "manage/talent_pools/talent_pool_membership_card",
             locals: { person: @person, production: @talent_pool.production }
    end

    def remove_from_cast
      @talent_pool = TalentPool.find(params[:talent_pool_id])
      @person = Current.organization.people.find(params[:person_id])
      @talent_pool.people.delete(@person) if @talent_pool.people.include?(@person)
      render partial: "manage/talent_pools/talent_pool_membership_card",
             locals: { person: @person, production: @talent_pool.production }
    end

    def remove_from_organization
      @person = Current.organization.people.find(params[:id])

      # Remove the person from the organization
      Current.organization.people.delete(@person)

      # If the person has a user account, clean up their roles and permissions
      if @person.user
        # Remove organization_role for this organization
        @person.user.organization_roles.where(organization: Current.organization).destroy_all

        # Remove production_permissions for all productions in this production company
        production_ids = Current.organization.productions.pluck(:id)
        @person.user.production_permissions.where(production_id: production_ids).destroy_all
      end

      redirect_to manage_people_path, notice: "#{@person.name} was removed from #{Current.organization.name}",
                                      status: :see_other
    end

    def contact
      @person = Current.organization.people.find(params[:id])
    end

    def send_contact_email
      @person = Current.organization.people.find(params[:id])
      subject = params[:subject]
      message = params[:message]

      if subject.present? && message.present?
        Manage::PersonMailer.contact_email(@person, subject, message, Current.user).deliver_later
        redirect_to manage_person_path(@person), notice: "Email sent to #{@person.name}"
      else
        redirect_to contact_manage_person_path(@person), alert: "Subject and message are required"
      end
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_person
      @person = Current.organization.people.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def person_params
      params.require(:person).permit(
        :name, :email, :pronouns, :resume, :headshot, :producer_notes,
        socials_attributes: %i[id platform handle name _destroy]
      )
    end
  end
end
