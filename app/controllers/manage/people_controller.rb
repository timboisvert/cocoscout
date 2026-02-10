# frozen_string_literal: true

module Manage
  class PeopleController < Manage::ManageController
    before_action :set_person, only: %i[show update update_availability availability_modal]
    before_action :ensure_user_is_global_manager, except: %i[show remove_from_organization availability_modal]

    def show
      # Person detail view
    end

    def new
      @person = Person.new
      load_talent_pools
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

    # AJAX endpoint to search for people to invite
    def search_for_invite
      q = params[:q].to_s.strip

      if q.blank? || q.length < 2
        render partial: "manage/people/invite_search_results",
               locals: {
                 org_members: [],
                 global_people: [],
                 query: q,
                 show_invite: false
               }
        return
      end

      # Search within organization (people only)
      org_people = Current.organization.people.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q) OR LOWER(public_key) LIKE LOWER(:q)",
        q: "%#{q}%"
      ).limit(10).to_a

      # Search globally in CocoScout (people not in this org)
      org_person_ids = Current.organization.people.pluck(:id)
      global_people = Person.where(
        "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q) OR LOWER(public_key) LIKE LOWER(:q)",
        q: "%#{q}%"
      ).where.not(id: org_person_ids).limit(10).to_a

      # Determine if we should show invite option
      # Show invite if query looks like an email and we didn't find exact matches
      show_invite = q.include?("@") && org_people.none? { |m| m.email&.downcase == q.downcase } &&
                   global_people.none? { |p| p.email&.downcase == q.downcase }

      render partial: "manage/people/invite_search_results",
             locals: {
               org_members: org_people,
               global_people: global_people,
               query: q,
               show_invite: show_invite
             }
    end

    private

    def selected_talent_pool
      return nil if params[:invite_to_pool] == "no"
      return nil if params[:talent_pool_id].blank?

      # Verify the talent pool belongs to this organization
      TalentPool.joins(:production)
                .where(productions: { organization_id: Current.organization.id })
                .find_by(id: params[:talent_pool_id])
    end

    def invite_selected_profiles(profile_ids)
      profiles = Person.where(id: profile_ids, email: person_params[:email]&.downcase)
      talent_pool = selected_talent_pool
      invitation_subject = params[:invitation_subject]
      invitation_body = params[:invitation_body]

      invited_names = []

      profiles.each do |person|
        # Note: We don't add the person to the organization here.
        # They will be added when they accept the invitation.

        # Create user if needed
        if person.user.nil?
          user = User.create!(
            email_address: person.email,
            password: User.generate_secure_password
          )
          person.update!(user: user)
        end

        # Create and send invitation
        person_invitation = PersonInvitation.create!(
          email: person.email,
          organization: Current.organization,
          talent_pool: talent_pool
        )
        Manage::PersonMailer.person_invitation(person_invitation, subject: invitation_subject, body: invitation_body).deliver_later

        invited_names << person.name
      end

      if invited_names.count == 1
        redirect_to new_manage_person_path, notice: "Invitation sent to #{invited_names.first}"
      else
        redirect_to new_manage_person_path, notice: "Invitations sent to #{invited_names.to_sentence}"
      end
    end

    def invite_single_profile(person)
      # Validate email before proceeding
      unless person.email.present? && person.email.match?(URI::MailTo::EMAIL_REGEXP)
        redirect_to [ :manage, person ], alert: "Cannot send invitation: #{person.email.presence || 'No email'} is not a valid email address"
        return
      end

      # Note: We don't add the person to the organization here.
      # They will be added when they accept the invitation.

      if person.user.nil?
        user = User.new(
          email_address: person.email,
          password: User.generate_secure_password
        )
        unless user.save
          redirect_to [ :manage, person ], alert: "Cannot create user account: #{user.errors.full_messages.join(', ')}"
          return
        end
        person.update!(user: user)
      end

      talent_pool = selected_talent_pool

      person_invitation = PersonInvitation.create!(
        email: person.email,
        organization: Current.organization,
        talent_pool: talent_pool
      )
      invitation_subject = params[:invitation_subject]
      invitation_body = params[:invitation_body]
      Manage::PersonMailer.person_invitation(person_invitation, subject: invitation_subject, body: invitation_body).deliver_later

      redirect_to new_manage_person_path,
                  notice: "Invitation sent to #{person.name}"
    end

    def create_new_person_and_invite
      @person = Person.new(person_params)

      if @person.save
        # Note: We don't add the person to the organization here.
        # They will be added when they accept the invitation.

        user = User.create!(
          email_address: @person.email,
          password: User.generate_secure_password
        )
        @person.update!(user: user)

        talent_pool = selected_talent_pool

        person_invitation = PersonInvitation.create!(
          email: @person.email,
          organization: Current.organization,
          talent_pool: talent_pool
        )
        invitation_subject = params[:invitation_subject]
        invitation_body = params[:invitation_body]
        Manage::PersonMailer.person_invitation(person_invitation, subject: invitation_subject, body: invitation_body).deliver_later

        redirect_to new_manage_person_path, notice: "Invitation sent to #{@person.name}"
      else
        render :new, status: :unprocessable_entity
      end
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
      current_status_for_response = nil
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

        # Track current status for response when no change is made
        current_status_for_response ||= current_status || new_status

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
          # Always return the current status - don't error if no changes made
          render json: { status: last_status || current_status_for_response }
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

    # Returns HTML for member availability modal
    def availability_modal
      # Get all future shows for productions this person is a member of
      # via direct talent pools or shared talent pools
      direct_production_ids = TalentPool.joins(:talent_pool_memberships)
                                        .where(talent_pool_memberships: { member: @person })
                                        .pluck(:production_id)

      # Also get productions that share a talent pool this person is in
      shared_production_ids = TalentPoolShare.joins(talent_pool: :talent_pool_memberships)
                                             .where(talent_pool_memberships: { member: @person })
                                             .pluck(:production_id)

      production_ids = (direct_production_ids + shared_production_ids).uniq

      @shows = Show.where(production_id: production_ids, canceled: false)
                   .where("date_and_time >= ?", Time.current)
                   .includes(:production, :location)
                   .order(:date_and_time)

      # Build a hash of availabilities: { show_id => show_availability }
      @availabilities = {}
      @person.show_availabilities.where(show: @shows).each do |availability|
        @availabilities[availability.show_id] = availability
      end

      render partial: "manage/people/availability_modal", locals: {
        member: @person,
        shows: @shows,
        availabilities: @availabilities,
        current_production_id: params[:production_id].to_s
      }
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

    # Load all talent pools available for invitations
    def load_talent_pools
      # In single mode, only show the org pool
      if Current.organization.talent_pool_single? && Current.organization.organization_talent_pool
        @talent_pools = [ Current.organization.organization_talent_pool ]
        @talent_pool_options = [ {
          pool: Current.organization.organization_talent_pool,
          display_name: Current.organization.name
        } ]
        return
      end

      # Get productions in this org that have received a share from another pool (they don't use their own)
      org_production_ids = Current.organization.productions.pluck(:id)
      productions_receiving_shares = TalentPoolShare.where(production_id: org_production_ids).pluck(:production_id)

      # Find pools, excluding those whose productions receive shares from elsewhere
      all_pools = TalentPool.joins(:production)
                            .includes(:production, :shared_productions)
                            .where(productions: { organization_id: Current.organization.id })
                            .where.not(production_id: productions_receiving_shares)
                            .order(:name)

      # Deduplicate by production - keep the pool that has shares, or the first one if none have shares
      pools_by_production = all_pools.group_by(&:production_id)
      pools = pools_by_production.values.map do |production_pools|
        # Prefer pool with shares, otherwise take the first one
        production_pools.find { |p| p.shared_productions.any? } || production_pools.first
      end.compact.sort_by { |p| p.name.downcase }

      # Build display options
      @talent_pool_options = pools.map do |pool|
        shared_prod_names = pool.shared_productions.pluck(:name)

        display_name = if shared_prod_names.any?
          # Shared pool: "Show1 / Show2 / Show3"
          all_names = [ pool.production.name ] + shared_prod_names
          all_names.join(" / ")
        else
          # Single production pool: just show production name
          pool.production.name
        end

        { pool: pool, display_name: display_name }
      end

      @talent_pools = pools
    end
  end
end
