# frozen_string_literal: true

module Manage
  class OrganizationsController < Manage::ManageController
    before_action :set_organization, only: %i[show edit update destroy transfer_ownership remove_logo confirm_delete]
    skip_before_action :show_manage_sidebar, only: %i[new create index edit]
    before_action :ensure_user_is_owner, only: %i[destroy transfer_ownership confirm_delete]
    before_action :ensure_user_can_manage, only: %i[show edit update remove_logo]

    def index
      # Management screen - list all organizations with management options
      @organizations = Current.user.accessible_organizations.includes(:owner, :productions, :users).order(:name)

      # Add role information for each organization
      @organization_roles = {}
      @organizations.each do |org|
        @organization_roles[org.id] = org.role_for(Current.user)
      end
    end

    # The organization page is a settings page: each topic is a routed section,
    # so only that section's data loads and links name the section they want.
    SECTIONS = %w[basic team locations agreements billing danger].freeze
    SECTION_LABELS = {
      "basic" => "Basic Information",
      "team" => "Team Members",
      "locations" => "Locations",
      "agreements" => "Agreements",
      "billing" => "Billing & Plan",
      "danger" => "Danger Zone"
    }.freeze
    DEFAULT_SECTION = "basic"

    def show
      @role = @organization.role_for(Current.user)
      @is_owner = @organization.owned_by?(Current.user)
      @section = requested_section
      return if performed?

      load_section_data
    end

    def new
      @organization = Organization.new
    end

    def edit; end

    def create
      @organization = Organization.new(organization_params)
      @organization.owner = Current.user
      # Campaign attribution, carried in the session since the marketing page
      # was several requests ago. Set from the session rather than
      # organization_params on purpose — a crafted form post can't fake it.
      @organization.referral_source = session[:referral_source]

      if @organization.save
        # Assign creator as manager via organization role
        OrganizationRole.create!(user: Current.user, organization: @organization, company_role: "manager")

        ensure_person_in_organization!(@organization)

        # Set as current organization
        session[:current_organization_id] ||= {}
        session[:current_organization_id][Current.user&.id.to_s] = @organization.id

        # If they chose Pro at signup, take them straight into checkout. The org
        # stays on the free tier until Stripe confirms the subscription.
        if params[:plan] == "pro"
          interval = %w[month year].include?(params[:interval]) ? params[:interval] : "year"
          redirect_to manage_billing_path(upgrade: interval) and return
        end

        redirect_to_intent_or(manage_path, notice: "#{@organization.name} was successfully created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @organization.update(organization_params)
        redirect_to manage_organization_path(@organization), notice: "Organization was successfully updated",
                                                             status: :see_other
      else
        # Re-setup show page instance variables for rendering
        @role = @organization.role_for(Current.user)
        @is_owner = @organization.owned_by?(Current.user)
        @team_members = @organization.users.includes(:default_person, :organization_roles)
        @team_invitations = @organization.team_invitations.where(accepted_at: nil, production_id: nil)
        @locations = @organization.locations.order(:created_at)
        @team_invitation = TeamInvitation.new
        @productions = @organization.productions.order(:name)
        @agreement_templates = @organization.agreement_templates.order(:name)
        render :show, status: :unprocessable_entity
      end
    end

    def destroy
      name = @organization.name
      @organization.destroy!

      # Clear from session if it was current
      session[:current_organization_id]&.delete(Current.user.id.to_s)

      redirect_to manage_organizations_path, notice: "#{name} was successfully deleted", status: :see_other
    end

    def remove_logo
      @organization.logo.purge
      redirect_back fallback_location: manage_organization_path(@organization), notice: "Logo removed successfully"
    end

    def confirm_delete
      @stats = {
        productions: @organization.productions.count,
        shows: @organization.productions.joins(:shows).count,
        people: @organization.people.count,
        groups: @organization.groups.count,
        locations: @organization.locations.count,
        team_members: @organization.users.count
      }
    end

    def transfer_ownership
      new_owner = User.find(params[:new_owner_id]) # rubocop:disable CocoScout/UnscopedFind -- new owner verified as a manager of @organization immediately below

      # Ensure new owner has manager role
      unless @organization.organization_roles.exists?(user: new_owner, company_role: "manager")
        redirect_to manage_organization_path(@organization), alert: "New owner must be a manager first"
        return
      end

      @organization.update!(owner: new_owner)
      redirect_to manage_organization_path(@organization),
                  notice: "Ownership transferred to #{new_owner.person&.name || new_owner.email_address}"
    end

    def setup_guide; end

    private

    # Danger Zone is the owner's alone, so it isn't even in the strip for anyone else.
    def available_sections
      @is_owner ? SECTIONS : SECTIONS - [ "danger" ]
    end

    def sections
      available_sections.map do |key|
        { key: key, label: SECTION_LABELS[key],
          path: section_manage_organization_path(@organization, section: key) }
      end
    end
    helper_method :sections

    def requested_section
      section = params[:section].presence || DEFAULT_SECTION
      return section if section.in?(available_sections)

      redirect_to manage_organization_path(@organization)
      DEFAULT_SECTION
    end

    def load_section_data
      case @section
      when "team"
        @team_members = @organization.users.includes(:default_person, :organization_roles)
        @team_invitations = @organization.team_invitations.where(accepted_at: nil, production_id: nil)
        @team_invitation = TeamInvitation.new
      when "locations"
        @locations = @organization.locations.order(:created_at)
      when "agreements"
        @agreement_templates = @organization.agreement_templates.order(:name)
      when "danger"
        # Transfer Ownership only offers itself when there's someone to transfer to.
        @team_members = @organization.users.includes(:default_person, :organization_roles)
      end
    end

    def set_organization
      @organization = Organization.find(params[:id]) # rubocop:disable CocoScout/UnscopedFind -- ensure_user_can_manage/ensure_user_is_owner before_action gates access
    end

    def organization_params
      params.expect(organization: %i[name logo])
    end

    def ensure_user_is_owner
      return if @organization.owned_by?(Current.user)

      redirect_to manage_organizations_path, alert: "Only the owner can perform this action"
    end

    def ensure_user_can_manage
      return if @organization.manageable_by?(Current.user)

      redirect_to manage_organizations_path, alert: "You don't have permission to manage this organization"
    end
  end
end
