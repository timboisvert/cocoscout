class Manage::PeopleController < Manage::ManageController
  before_action :set_person, only: %i[ show edit update destroy update_availability ]
  before_action :ensure_user_is_global_manager, except: %i[show remove_from_organization]

  def show
    # Get all future shows for productions this person is a cast member of
    production_ids = @person.talent_pools.pluck(:production_id).uniq
    @shows = Show.where(production_id: production_ids, canceled: false)
                 .where("date_and_time >= ?", Time.current)
                 .order(:date_and_time)

    # Build a hash of availabilities: { show_id => show_availability }
    @availabilities = {}
    @person.show_availabilities.where(show: @shows).each do |availability|
      @availabilities[availability.show_id] = availability
    end

    # Track edit mode
    @edit_mode = params[:edit] == "true"
  end

  def new
    @person = Person.new
  end

  def edit
  end

  def create
    # Check if a user with this email already exists
    existing_user = User.find_by(email_address: person_params[:email])

    # Check if a person with this email already exists
    existing_person = Person.find_by(email: person_params[:email])

    if existing_user && existing_user.person
      # User and person both exist - just add to production company if not already
      existing_person = existing_user.person
      unless existing_person.organizations.include?(Current.organization)
        existing_person.organizations << Current.organization
      end

      redirect_to [ :manage, existing_person ], notice: "#{existing_person.name} has been added to #{Current.organization.name}"
    elsif existing_person
      # Person exists but no user - create user and link them
      unless existing_person.organizations.include?(Current.organization)
        existing_person.organizations << Current.organization
      end

      user = User.create!(
        email_address: existing_person.email,
        password: SecureRandom.hex(16)
      )
      existing_person.update!(user: user)

      # Create person invitation with production company context
      person_invitation = PersonInvitation.create!(
        email: existing_person.email,
        organization: Current.organization
      )

      # Send invitation email
      invitation_subject = params[:person][:invitation_subject] || "You've been invited to join #{Current.organization.name} on CocoScout"
      invitation_message = params[:person][:invitation_message] || "Welcome to CocoScout!\n\n#{Current.organization.name} is using CocoScout to manage its productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."
      Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later

      redirect_to [ :manage, existing_person ], notice: "User account created and invitation sent to #{existing_person.name}"
    else
      # Create both person and user
      @person = Person.new(person_params)
      if @person.save
        # Associate with current production company
        @person.organizations << Current.organization

        user = User.create!(
          email_address: @person.email,
          password: SecureRandom.hex(16)
        )
        @person.update!(user: user)

        # Create person invitation with production company context
        person_invitation = PersonInvitation.create!(
          email: @person.email,
          organization: Current.organization
        )

        # Send invitation email
        invitation_subject = params[:person][:invitation_subject] || "You've been invited to join #{Current.organization.name} on CocoScout"
        invitation_message = params[:person][:invitation_message] || "Welcome to CocoScout!\n\n#{Current.organization.name} is using CocoScout to manage its productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."
        Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later

        redirect_to [ :manage, @person ], notice: "Person was successfully created and invitation sent"
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def update
    if @person.update(person_params)
      redirect_to [ :manage, @person ], notice: "Person was successfully updated", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def update_availability
    # Update availabilities for each show
    params.each do |key, value|
      if key.match?(/^availability_/)
        show_id = key.match(/availability_(\d+)/)[1].to_i
        show = Show.find(show_id)
        availability = @person.show_availabilities.find_or_initialize_by(show: show)

        if value == "available"
          availability.available!
        elsif value == "unavailable"
          availability.unavailable!
        end

        availability.save
      end
    end

    redirect_to manage_person_path(@person, tab: 2, edit: "true"), notice: "Availability updated"
  end

  def destroy
    user = @person.user

    # Manually destroy associations that don't have dependent: :destroy
    @person.auditions.destroy_all

    # Remove from join tables
    @person.talent_pools.clear
    @person.organizations.clear

    # Destroy the user first (which will nullify the person association)
    user&.destroy!

    # Now destroy the person (dependent associations will be handled automatically)
    @person.destroy!

    redirect_to manage_people_path, notice: "Person was successfully deleted", status: :see_other
  end

  def batch_invite
    emails_text = params[:emails].to_s
    email_lines = emails_text.split(/\r?\n/).map(&:strip).reject(&:blank?)

    invitation_subject = params[:invitation_subject] || "You've been invited to join #{Current.organization.name} on CocoScout"
    invitation_message = params[:invitation_message] || "Welcome to CocoScout!\n\n#{Current.organization.name} is using CocoScout to manage its productions, auditions, and casting.\n\nTo get started, please click the link below to set a password and create your account."

    invited_count = 0
    skipped_count = 0
    errors = []

    email_lines.each do |email|
      # Validate email format
      unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
        errors << "Invalid email format: #{email}"
        next
      end

      # Check if user already exists
      if User.exists?(email_address: email.downcase)
        skipped_count += 1
        next
      end

      # Check if person already exists
      existing_person = Person.find_by(email: email.downcase)

      if existing_person
        # Person exists but may or may not have a user
        if existing_person.user
          # Person and user both exist - skip
          skipped_count += 1
          next
        else
          # Person exists but no user - create user and send invitation
          person = existing_person
        end
      else
        # Generate name from email (part before @)
        name = email.split("@").first.gsub(/[._-]/, " ").titleize

        # Create person
        person = Person.new(name: name, email: email.downcase)
      end

      if person.save
        # Associate with current production company (in case it's a new person)
        unless person.organizations.include?(Current.organization)
          person.organizations << Current.organization
        end

        # Create user account if it doesn't exist
        if person.user.nil?
          user = User.create!(
            email_address: person.email,
            password: SecureRandom.hex(16)
          )
          person.update!(user: user)
        end

        # Create person invitation
        person_invitation = PersonInvitation.create!(
          email: person.email,
          organization: Current.organization
        )

        # Send invitation email
        Manage::PersonMailer.person_invitation(person_invitation, invitation_subject, invitation_message).deliver_later

        invited_count += 1
      else
        errors << "Failed to create person for #{email}: #{person.errors.full_messages.join(', ')}"
      end
    end

    # Build notice message
    notice_parts = []
    notice_parts << "#{invited_count} #{'person'.pluralize(invited_count)} invited" if invited_count > 0
    notice_parts << "#{skipped_count} skipped (already exists)" if skipped_count > 0

    if errors.any?
      redirect_to new_manage_person_path, alert: "Errors occurred: #{errors.join('; ')}"
    else
      redirect_to manage_people_path, notice: notice_parts.join(", ")
    end
  end

  def add_to_cast
    @talent_pool = TalentPool.find(params[:talent_pool_id])
    @person = Current.organization.people.find(params[:person_id])
    @talent_pool.people << @person if !@talent_pool.people.include?(@person)
    render partial: "manage/talent_pools/talent_pool_membership_card", locals: { person: @person, production: @talent_pool.production }
  end

  def remove_from_cast
    @talent_pool = TalentPool.find(params[:talent_pool_id])
    @person = Current.organization.people.find(params[:person_id])
    @talent_pool.people.delete(@person) if @talent_pool.people.include?(@person)
    render partial: "manage/talent_pools/talent_pool_membership_card", locals: { person: @person, production: @talent_pool.production }
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

    redirect_to manage_people_path, notice: "#{@person.name} was removed from #{Current.organization.name}", status: :see_other
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
        :name, :email, :pronouns, :resume, :headshot,
        socials_attributes: [ :id, :platform, :handle, :_destroy ]
      )
    end
end
