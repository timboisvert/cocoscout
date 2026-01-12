# frozen_string_literal: true

module Manage
  class RolesController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :set_role, only: %i[edit update destroy]
    before_action :ensure_user_is_manager, except: %i[index]
    before_action :load_talent_pool_members, only: %i[index]

    def index
      @roles = @production.roles.order(:position, :created_at)
      @role = @production.roles.new
    end

    def edit; end

    def create
      @roles = @production.roles.order(:position, :created_at)
      @role = @production.roles.new(role_params)

      # Set position to be at the end of the list
      max_position = @production.roles.maximum(:position) || -1
      @role.position = max_position + 1

      if @role.save
        update_eligible_members(@role)
        redirect_to manage_production_roles_path(@production), notice: "Role was successfully created"
      else
        load_talent_pool_members
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @role.update(role_params)
        update_eligible_members(@role)
        redirect_to manage_production_roles_path(@production), notice: "Role was successfully updated",
                                                               status: :see_other
      else
        @roles = @production.roles.order(:position, :created_at)
        load_talent_pool_members
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @role.destroy!
      redirect_to manage_production_roles_path(@production), notice: "Role was successfully deleted", status: :see_other
    end

    def reorder
      role_ids = params[:role_ids]
      role_ids.each_with_index do |id, index|
        @production.roles.find(id).update(position: index)
      end
      head :ok
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.expect(:production_id))
      sync_current_production(@production)
    end

    def set_role
      @role = @production.roles.find(params.expect(:id))
    end

    def load_talent_pool_members
      talent_pool = @production.talent_pool

      if talent_pool
        people = Person.joins(:talent_pool_memberships)
                       .where(talent_pool_memberships: { talent_pool_id: talent_pool.id })
                       .includes(profile_headshots: { image_attachment: :blob })
                       .distinct

        groups = Group.joins(:talent_pool_memberships)
                      .where(talent_pool_memberships: { talent_pool_id: talent_pool.id })
                      .includes(profile_headshots: { image_attachment: :blob })
                      .distinct

        @talent_pool_members = (people.to_a + groups.to_a).sort_by(&:name)
      else
        @talent_pool_members = []
      end
    end

    def update_eligible_members(role)
      # Parse member IDs in format "Person_123" or "Group_456"
      eligible_member_ids = params.dig(:role, :eligible_member_ids)&.reject(&:blank?) || []

      if role.restricted? && eligible_member_ids.any?
        # Parse the member type and ID from each entry
        new_members = eligible_member_ids.map do |member_key|
          type, id = member_key.split("_", 2)
          { member_type: type, member_id: id.to_i }
        end

        # Remove eligibilities that are no longer selected
        role.role_eligibilities.each do |eligibility|
          member_key = { member_type: eligibility.member_type, member_id: eligibility.member_id }
          eligibility.destroy unless new_members.include?(member_key)
        end

        # Add new eligibilities
        existing_keys = role.role_eligibilities.reload.map { |e| { member_type: e.member_type, member_id: e.member_id } }
        new_members.each do |member|
          unless existing_keys.include?(member)
            role.role_eligibilities.create!(member_type: member[:member_type], member_id: member[:member_id])
          end
        end
      else
        role.role_eligibilities.destroy_all
      end
    end

    # Only allow a list of trusted parameters through.
    def role_params
      params.expect(role: [ :name, :restricted, :quantity, :category ])
    end
  end
end
