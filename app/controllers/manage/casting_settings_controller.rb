# frozen_string_literal: true

module Manage
  # Per-production casting settings, on the shared settings layout: each topic
  # is its own routed section, so only that section's data loads.
  class CastingSettingsController < ManageController
    include CastingHelper

    SECTIONS = %w[source roles talent_pool dates].freeze
    SECTION_LABELS = {
      "source" => "Casting Source",
      "roles" => "Roles",
      "talent_pool" => "Talent Pool",
      "dates" => "Dates"
    }.freeze
    DEFAULT_SECTION = "source"

    before_action :set_production
    # Production team viewers look; managers change things (Tim, 2026-10-17).
    before_action :ensure_user_is_manager
    before_action :set_section, only: [ :show ]
    before_action :load_section_data, only: [ :show ]

    def show; end

    def update
      was_act_based = @production.act_based?
      if @production.update(casting_settings_params)
        # Roles → acts reshapes the lineup (Dancer ×5 becomes five Dancer acts,
        # cast kept); acts → roles folds same-named runs back into one role.
        if !was_act_based && @production.act_based?
          CastingModeConverter.to_acts!(@production)
        elsif was_act_based && @production.role_based?
          CastingModeConverter.to_roles!(@production)
        end

        respond_to do |format|
          format.html { redirect_to manage_casting_settings_path(@production), notice: "Casting settings updated." }
          format.turbo_stream { head :ok }
        end
      else
        @section = DEFAULT_SECTION
        load_section_data
        render :show, status: :unprocessable_content
      end
    end

    # The production's answer (Tim, 2026-11-18): "We cast people in this
    # production" or "We don't cast people in this production". The coming
    # dates are brought into line with it (CastingAnswer). return_to: the
    # page the answer was given on, when that isn't Casting Settings (the
    # production's page, its Casting tab).
    def update_answer
      answer = params[:casts_people].to_s
      if answer == "no"
        CastingAnswer.off!(@production)
        notice = "We don't cast people in #{@production.name}. You can change this in Casting Settings."
      elsif answer == "yes"
        CastingAnswer.on!(@production)
        notice = "We cast people in #{@production.name}."
      end
      redirect_to answer_return_path, notice: notice
    end

    # Which of the coming dates are cast (the Dates section).
    def update_dates
      CastingAnswer.choose_dates!(@production, params[:show_ids])
      redirect_to manage_casting_settings_section_path(production_id: @production, section: "dates"), notice: "The dates were updated."
    end

    private

    # Only a path on this site, and only one of the two pages the answer is
    # asked on outside Casting Settings.
    def answer_return_path
      case params[:return_to].to_s
      when "production" then manage_production_path(@production)
      when "production_edit" then edit_manage_production_path(@production, tab: helpers.production_casting_tab(@production))
      else manage_casting_settings_path(@production)
      end
    end

    def sections
      SECTIONS.map do |key|
        { key: key, label: section_label(key),
          path: manage_casting_settings_section_path(production_id: @production, section: key) }
      end
    end
    helper_method :sections

    # The roles section is the "Lineup" in an act-based production.
    def section_label(key)
      return casting_structure_label(@production) if key == "roles"

      SECTION_LABELS[key]
    end
    helper_method :section_label

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
      when "dates"
        @dates = CastingAnswer.upcoming(@production).includes(:location, :location_space, linked_show: { production: :organization }).to_a
        @cast_ids = CastingAnswer.cast_show_ids(@production).to_set
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
      permitted = params.require(:production).permit(:casting_source, :casting_mode, :default_signup_based_casting, :default_attendance_enabled)
      # An unknown mode would raise out of the enum; drop it instead.
      if permitted.key?(:casting_mode) && !Production.casting_modes.key?(permitted[:casting_mode].to_s)
        permitted.delete(:casting_mode)
      end
      permitted
    end
  end
end
