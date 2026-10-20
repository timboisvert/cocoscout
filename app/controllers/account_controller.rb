# frozen_string_literal: true

class AccountController < ApplicationController
  skip_before_action :show_my_sidebar
  before_action :set_account_sidebar
  before_action :set_profile, only: [ :set_default_profile, :archive_profile ]

  # Rate limit: can only change email once per 24 hours
  EMAIL_CHANGE_COOLDOWN = 24.hours

  def show
    @person = Current.user.person
    @app_sessions = Current.user.app_sessions.live.order(last_used_at: :desc)
    @other_sessions = Current.user.sessions.where.not(id: Current.session.id).order(created_at: :desc)
  end

  def update
    if Current.user.update(user_params)
      redirect_to account_path, notice: "Account updated successfully."
    else
      render :show, status: :unprocessable_content
    end
  end

  def update_email
    new_email = params[:email_address]&.strip&.downcase

    # Check rate limit
    if Current.user.email_changed_at.present? && Current.user.email_changed_at > EMAIL_CHANGE_COOLDOWN.ago
      render json: { success: false, error: "You've changed your email too recently. Please try again later." }, status: :unprocessable_content
      return
    end

    # Check if email is same as current
    if new_email == Current.user.email_address
      render json: { success: false, error: "This is already your email address." }, status: :unprocessable_content
      return
    end

    # Check if email already exists
    if User.where.not(id: Current.user.id).exists?(email_address: new_email)
      render json: { success: false, error: "An account with this email address already exists." }, status: :unprocessable_content
      return
    end

    # Get profile IDs to update
    profile_ids_to_update = params[:profile_ids] || []

    ActiveRecord::Base.transaction do
      old_email = Current.user.email_address

      # Update user email
      Current.user.update!(email_address: new_email, email_changed_at: Time.current)

      # Update selected profile emails
      if profile_ids_to_update.any?
        Current.user.people.where(id: profile_ids_to_update).each do |person|
          person.update!(email: new_email) if person.email == old_email
        end
      end
    end

    render json: { success: true, message: "Email updated successfully." }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_content
  end

  def profiles
    @profiles = Current.user.people.active.order(:created_at)
    @default_profile = Current.user.default_person
    @groups = Current.user.person&.groups&.active&.includes(:group_memberships) || []
  end

  def create_profile
    @profile = Person.new(profile_params)
    @profile.user = Current.user
    @profile.email = Current.user.email_address if @profile.email.blank?

    if @profile.save
      if params[:set_as_default] == "1" || Current.user.people.active.count == 1
        Current.user.set_default_person!(@profile)
      end
      redirect_to account_profiles_path, notice: "Profile created successfully."
    else
      @profiles = Current.user.people.active.order(:created_at)
      @default_profile = Current.user.default_person
      render :profiles, status: :unprocessable_content
    end
  end

  def set_default_profile
    Current.user.set_default_person!(@profile)
    redirect_to account_profiles_path, notice: "\"#{@profile.name}\" is now your default profile."
  end

  def archive_profile
    if @profile.default_profile? && Current.user.people.active.count == 1
      redirect_to account_profiles_path, alert: "You cannot archive your only profile."
      return
    end

    if @profile.default_profile?
      new_default = Current.user.people.active.where.not(id: @profile.id).order(:created_at).first
      Current.user.update!(default_person: new_default)
    end

    @profile.archive!
    redirect_to account_profiles_path, notice: "Profile archived."
  end

  def notifications
    # Ticketing: the organizations where this person is a manager, each with
    # the email plan the organization gave them (TicketingNotifications).
    @ticketing_plans = Current.user.accessible_organizations.filter_map do |organization|
      settings = TicketingNotifications.new(organization)
      recipient = settings.recipient("user:#{Current.user.id}")
      [ organization, recipient ] if recipient
    end
  end

  # Email notification preferences. Only the keys a form sends change, so a
  # form showing some of them (the app's /my/account) never switches the rest
  # off. Each toggle sends a hidden "0" before its checkbox, so an unchecked
  # box still arrives.
  def update_notifications
    notification_params = params[:notifications] || {}
    User::NOTIFICATION_PREFERENCE_KEYS.each do |key|
      next unless notification_params.key?(key)

      if key == "message_digest"
        # message_digest is a direct column, not in notification_preferences
        Current.user.message_digest_enabled = (notification_params[key] == "1")
      else
        enabled = notification_params[key] == "1"
        Current.user.set_notification_preference(key, enabled)
      end
    end

    # V1.1's groups: Push and Email per group (NotificationGroups).
    Current.user.set_notification_switches(push: params[:push]&.to_unsafe_h || {}, email: params[:email]&.to_unsafe_h || {})

    back = params[:return_to] == my_account_path ? my_account_path : account_notifications_path
    if Current.user.save
      redirect_to back, notice: "Notification settings saved."
    else
      redirect_to back, alert: "Failed to update notification preferences."
    end
  end

  def organizations
    @person = Current.user.person
    @people = Current.user.people.active.order(:created_at).to_a
    people_ids = @people.map(&:id)

    # Get groups from all profiles
    @groups = Group.active
                   .joins(:group_memberships)
                   .where(group_memberships: { person_id: people_ids })
                   .distinct
                   .order(:name)
                   .to_a
    group_ids = @groups.map(&:id)

    # Find all organizations the user is connected to via talent pools
    production_ids = Set.new

    # Productions via person memberships
    person_production_ids = TalentPoolMembership
      .where(member_type: "Person", member_id: people_ids)
      .joins(:talent_pool)
      .pluck("talent_pools.production_id")
    production_ids.merge(person_production_ids)

    # Productions via group memberships
    if group_ids.any?
      group_production_ids = TalentPoolMembership
        .where(member_type: "Group", member_id: group_ids)
        .joins(:talent_pool)
        .pluck("talent_pools.production_id")
      production_ids.merge(group_production_ids)
    end

    # Get all organizations from these productions
    org_ids = Production.where(id: production_ids).pluck(:organization_id).uniq

    # Also include organizations from organization_roles (team memberships)
    team_org_ids = Current.user.organization_roles.pluck(:organization_id)
    org_ids = (org_ids + team_org_ids).uniq

    # Also include organizations from people's directory memberships (HABTM)
    if people_ids.any?
      people_org_ids = Organization.joins(:people).where(people: { id: people_ids }).pluck(:id)
      org_ids = (org_ids + people_org_ids).uniq
    end

    @organizations = Organization.where(id: org_ids).includes(:productions, logo_attachment: :blob).order(:name)

    # Build lookup of connection types for each org
    @organization_connections = {}
    @organizations.each do |org|
      connections = {
        as_talent: false,
        as_team: false,
        production_count: 0,
        people: [],
        groups: []
      }

      # Check team membership
      if Current.user.organization_roles.exists?(organization_id: org.id)
        connections[:as_team] = true
      end

      # Check talent pool memberships
      org_production_ids = org.productions.pluck(:id)
      talent_pools = TalentPool.where(production_id: org_production_ids)

      @people.each do |person|
        if TalentPoolMembership.exists?(talent_pool: talent_pools, member: person)
          connections[:as_talent] = true
          connections[:people] << person
        end
      end

      @groups.each do |group|
        if TalentPoolMembership.exists?(talent_pool: talent_pools, member: group)
          connections[:as_talent] = true
          connections[:groups] << group
        end
      end

      connections[:production_count] = org_production_ids.count
      @organization_connections[org.id] = connections
    end
  end

  # Signs one phone out of the app; its token stops working at once.
  def sign_out_app
    session = Current.user.app_sessions.find(params[:id])
    session.destroy!
    redirect_to account_path, notice: "#{session.label} is signed out of the app."
  end

  # Signs one other browser or app phone out.
  def sign_out_session
    session = Current.user.sessions.where.not(id: Current.session.id).find(params[:id])
    session.destroy!
    redirect_to account_path, notice: "#{session.label} is signed out."
  end

  # Signs out everywhere but here: every other browser, app phone and API
  # sign-in.
  def sign_out_elsewhere
    Current.user.sessions.where.not(id: Current.session.id).destroy_all
    Current.user.app_sessions.destroy_all
    redirect_to account_path, notice: "You're signed out everywhere but here."
  end

  # Delete my account, from the website or the app (Apple requires the app to
  # offer it). It's a request: the superadmins get an email and finish it
  # within 30 days from the person's Superadmin page, keeping the payout and
  # tax records the law needs. Until then it can be taken back.
  def request_deletion
    user = Current.user
    unless user.deletion_requested_at
      user.update!(deletion_requested_at: Time.current)
      AccountDeletionRequest.notify_superadmins(user, from_app: turbo_native_app?, device: DeviceLabel.device_name(request.user_agent.to_s))
    end
    redirect_to account_path, notice: "We've got your request. Your account will be deleted within 30 days."
  end

  def cancel_deletion
    Current.user.update!(deletion_requested_at: nil)
    redirect_to account_path, notice: "Your account won't be deleted."
  end

  def leave_organization
    organization = Organization.find(params[:id])
    @people = Current.user.people.active.to_a
    people_ids = @people.map(&:id)

    # Get groups from all profiles
    group_ids = Group.active
                     .joins(:group_memberships)
                     .where(group_memberships: { person_id: people_ids })
                     .pluck(:id)

    # Get all production IDs for this organization
    production_ids = organization.productions.pluck(:id)
    talent_pool_ids = TalentPool.where(production_id: production_ids).pluck(:id)

    ActiveRecord::Base.transaction do
      # Remove talent pool memberships for all profiles
      TalentPoolMembership.where(talent_pool_id: talent_pool_ids, member_type: "Person", member_id: people_ids).destroy_all

      # Remove talent pool memberships for groups
      if group_ids.any?
        TalentPoolMembership.where(talent_pool_id: talent_pool_ids, member_type: "Group", member_id: group_ids).destroy_all
      end

      # Remove all show assignments for this org's productions
      show_ids = Show.where(production_id: production_ids).pluck(:id)
      ShowPersonRoleAssignment.where(show_id: show_ids, assignable_type: "Person", assignable_id: people_ids).destroy_all
      if group_ids.any?
        ShowPersonRoleAssignment.where(show_id: show_ids, assignable_type: "Group", assignable_id: group_ids).destroy_all
      end

      # Remove audition requests
      AuditionRequest.where(requestable_type: "Person", requestable_id: people_ids)
                     .joins(:audition_window)
                     .joins("INNER JOIN audition_cycles ON audition_windows.audition_cycle_id = audition_cycles.id")
                     .where(audition_cycles: { production_id: production_ids })
                     .destroy_all

      if group_ids.any?
        AuditionRequest.where(requestable_type: "Group", requestable_id: group_ids)
                       .joins(:audition_window)
                       .joins("INNER JOIN audition_cycles ON audition_windows.audition_cycle_id = audition_cycles.id")
                       .where(audition_cycles: { production_id: production_ids })
                       .destroy_all
      end

      # Remove cast assignment stages
      CastAssignmentStage.where(assignable_type: "Person", assignable_id: people_ids, talent_pool_id: talent_pool_ids).destroy_all
      if group_ids.any?
        CastAssignmentStage.where(assignable_type: "Group", assignable_id: group_ids, talent_pool_id: talent_pool_ids).destroy_all
      end

      # Remove role eligibilities
      RoleEligibility.where(member_type: "Person", member_id: people_ids)
                     .joins(:role)
                     .where(roles: { production_id: production_ids })
                     .destroy_all

      if group_ids.any?
        RoleEligibility.where(member_type: "Group", member_id: group_ids)
                       .joins(:role)
                       .where(roles: { production_id: production_ids })
                       .destroy_all
      end

      # Remove vacancy invitations
      RoleVacancyInvitation.where(person_id: people_ids)
                           .joins(role_vacancy: { show_person_role_assignment: :show })
                           .where(shows: { production_id: production_ids })
                           .destroy_all

      # Remove show availabilities
      ShowAvailability.where(available_entity_type: "Person", available_entity_id: people_ids, show_id: show_ids).destroy_all
      if group_ids.any?
        ShowAvailability.where(available_entity_type: "Group", available_entity_id: group_ids, show_id: show_ids).destroy_all
      end
    end

    redirect_to account_organizations_path, notice: "You have been removed from #{organization.name}."
  end

  private

  def set_account_sidebar
    @show_account_sidebar = true
  end

  def set_profile
    @profile = Current.user.people.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email_address)
  end

  def profile_params
    params.require(:person).permit(:name, :email, :pronouns)
  end
end
