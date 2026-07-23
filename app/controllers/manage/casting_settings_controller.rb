# frozen_string_literal: true

module Manage
  # Per-production casting settings, on the shared settings layout: each topic
  # is its own routed section, so only that section's data loads.
  class CastingSettingsController < ManageController
    SECTIONS = %w[source roles talent_pool].freeze
    SECTION_LABELS = {
      "source" => "Casting Source",
      "roles" => "Roles",
      "talent_pool" => "Talent Pool"
    }.freeze
    DEFAULT_SECTION = "source"

    before_action :set_production
    before_action :set_section, only: [ :show ]
    before_action :load_section_data, only: [ :show ]

    def show; end

    def update
      if @production.update(casting_settings_params)
        respond_to do |format|
          format.html { redirect_to manage_casting_settings_path(@production), notice: "Casting settings updated." }
          format.turbo_stream { head :ok }
        end
      else
        @section = DEFAULT_SECTION
        load_section_data
        render :show, status: :unprocessable_entity
      end
    end

    private

    def sections
      SECTIONS.map do |key|
        { key: key, label: SECTION_LABELS[key],
          path: manage_casting_settings_section_path(production_id: @production, section: key) }
      end
    end
    helper_method :sections

    def set_section
      @section = params[:section].presence || DEFAULT_SECTION
      redirect_to manage_casting_settings_path(@production) unless @section.in?(SECTIONS)
    end

    # The source section needs nothing but the production; the others need the
    # roster and/or the pool they cast from.
    def load_section_data
      case @section
      when "roles"
        load_roles_data
        load_talent_pool_data
      when "talent_pool"
        load_talent_pool_data
      end
    end

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
