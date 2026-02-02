# frozen_string_literal: true

module Manage
  class CastingSettingsController < ManageController
    before_action :set_production
    before_action :load_roles_data, only: [ :show ]
    before_action :load_talent_pool_data, only: [ :show ]

    def show
      # Main casting settings page with tabs
    end

    def update
      if @production.update(casting_settings_params)
        respond_to do |format|
          format.html { redirect_to manage_casting_settings_path(@production), notice: "Casting settings updated." }
          format.turbo_stream { head :ok }
        end
      else
        load_roles_data
        load_talent_pool_data
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def load_roles_data
      @roles = @production.roles.order(:position, :created_at)
      @role = @production.roles.new
      load_talent_pool_members_for_roles
    end

    def load_talent_pool_data
      @talent_pool = @production.effective_talent_pool
    end

    def load_talent_pool_members_for_roles
      talent_pool = @production.effective_talent_pool

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

    def casting_settings_params
      params.require(:production).permit(:casting_source, :default_signup_based_casting, :default_attendance_enabled)
    end
  end
end
