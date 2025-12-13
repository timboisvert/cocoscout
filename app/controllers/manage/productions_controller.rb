# frozen_string_literal: true

module Manage
  class ProductionsController < Manage::ManageController
    before_action :set_production, only: %i[show edit update destroy confirm_delete check_url_availability update_public_key]
    before_action :check_production_access, only: %i[show edit update destroy confirm_delete check_url_availability update_public_key]
    before_action :ensure_user_is_global_manager, only: %i[new create]
    before_action :ensure_user_is_manager, only: %i[edit update destroy confirm_delete update_public_key]
    skip_before_action :show_manage_sidebar, only: %i[index new create]

    def index
      # Redirect to production selection
      redirect_to select_production_path
    end

    def show
      set_production_in_session
      @dashboard = DashboardService.new(@production).generate
    end

    def new
      @production = Current.organization.productions.new
    end

    def edit
      # Eager load posters for visual assets tab
      @production = Current.organization.productions.includes(:posters).find_by(id: params[:id])
    end

    def create
      @production = Current.organization.productions.new(production_params)

      if @production.save
        set_production_in_session
        # Auto-dismiss welcome screen after creating first production
        Current.user.update(welcomed_production_at: Time.current) if Current.user.welcomed_production_at.nil?
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      process_event_visibility_params
      process_cast_talent_pool_ids_params
      process_show_upcoming_event_types_params

      if @production.update(production_params)
        @production.reload  # Ensure we have the latest data
        set_production_in_session

        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("features_frame", partial: "manage/productions/features_card", locals: { production: @production }),
              turbo_stream.prepend("flash-messages", partial: "shared/notice", locals: { notice: "Settings saved" })
            ]
          end
          format.html { redirect_to [ :manage, @production ], notice: "Production was successfully updated", status: :see_other }
        end
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def confirm_delete
      # Gather stats about what will be deleted
      @shows_count = @production.shows.count
      @roles_count = @production.roles.count
      @posters_count = @production.posters.count
      @audition_cycles_count = @production.audition_cycles.count
      @questionnaires_count = @production.questionnaires.count
    end

    def check_url_availability
      proposed_key = params[:public_key]&.strip&.downcase

      result = PublicKeyService.validate(proposed_key, entity_type: :production, exclude_entity: @production)

      render json: result
    end

    def update_public_key
      new_key = params[:production][:public_key]&.strip&.downcase

      if @production.update_public_key(new_key)
        redirect_to edit_manage_production_path(@production, anchor: "tab-2"),
                    notice: "Public profile URL updated successfully"
      else
        redirect_to edit_manage_production_path(@production, anchor: "tab-2"),
                    alert: @production.errors[:public_key].first || "Failed to update URL"
      end
    end

    def destroy
      return unless Current.organization && Current.user

      session[:current_production_id_for_organization]["#{Current.user&.id}_#{Current.organization&.id}"] = nil
      @production.destroy!
      redirect_to manage_productions_path, notice: "Production was successfully deleted", status: :see_other and return
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_production
      @production = Current.organization.productions.find_by(id: params[:id])
      return if @production

      redirect_to manage_productions_path, alert: "Not authorized or not found" and return
    end

    def set_production_in_session
      return unless Current.organization && Current.user

      # Make sure we have the sessions hash set for production IDs
      session[:current_production_id_for_organization] ||= {}

      # Store the current one
      previous_production_id = session[:current_production_id_for_organization]&.dig("#{Current.user&.id}_#{Current.organization&.id}")

      # Set the new one
      session[:current_production_id_for_organization]["#{Current.user&.id}_#{Current.organization&.id}"] =
        @production.id

      # If the production changed, redirect to the manage home so the left nav resets
      return unless previous_production_id != @production.id

      redirect_to manage_path and return
    end

    # Only allow a list of trusted parameters through.
    # Note: cast_talent_pool_ids and show_upcoming_event_types are processed
    # before this method is called to convert arrays to JSON strings
    def production_params
      params.require(:production).permit(:name, :logo, :description,
                                         :contact_email, :public_key,
                                         :public_profile_enabled,
                                         :show_cast_members, :show_upcoming_events,
                                         :show_upcoming_events_mode,
                                         :show_upcoming_event_types,
                                         :cast_talent_pool_ids,
                                         :auto_create_event_pages, :auto_create_event_pages_mode,
                                         :event_visibility_overrides).merge(organization_id: Current.organization&.id)
    end

    # Convert event_visibility checkboxes to JSON stored in event_visibility_overrides
    def process_event_visibility_params
      return unless params[:production][:event_visibility].present?

      visibility_overrides = {}
      EventTypes.config.each_key do |event_type|
        # Checkbox present = visible (true), absent = hidden (false)
        visibility_overrides[event_type] = params[:production][:event_visibility][event_type] == "1"
      end

      params[:production][:event_visibility_overrides] = visibility_overrides.to_json
    end

    # Convert cast_talent_pool_ids array to JSON
    # When "all" is selected, clear any specific pool selections
    # When switching to "specific" mode for first time, initialize with all talent pool ids
    def process_cast_talent_pool_ids_params
      if params[:cast_pool_selection] == "all"
        params[:production][:cast_talent_pool_ids] = nil
        return
      end

      # When switching to "specific" mode, check if we need to initialize defaults
      if params[:cast_pool_selection] == "specific"
        # If checkboxes section was NOT rendered (first time switching to specific mode),
        # the key won't exist. If it exists (even as empty array with just ""), the section was rendered.
        checkboxes_were_rendered = params[:production].key?(:cast_talent_pool_ids)

        if !checkboxes_were_rendered && @production.parsed_cast_talent_pool_ids.empty?
          # First time switching to specific mode - initialize with talent pool id
          talent_pool = @production.talent_pool
          if talent_pool
            params[:production][:cast_talent_pool_ids] = [ talent_pool.id ].to_json
          end
          return
        end
      end

      return unless params[:production].key?(:cast_talent_pool_ids)

      pool_ids = params[:production][:cast_talent_pool_ids]
      # Filter out empty strings and convert to integers
      pool_ids = pool_ids.reject(&:blank?).map(&:to_i) if pool_ids.is_a?(Array)
      params[:production][:cast_talent_pool_ids] = pool_ids.present? ? pool_ids.to_json : "[]"
    end

    # Convert show_upcoming_event_types array to JSON
    # When "all" is selected, clear any specific event type selections
    # When switching to "specific" mode for first time, initialize with defaults
    def process_show_upcoming_event_types_params
      mode = params.dig(:production, :show_upcoming_events_mode)

      if mode == "all"
        params[:production][:show_upcoming_event_types] = nil
        return
      end

      # When switching to "specific" mode, check if we need to initialize defaults
      if mode == "specific"
        event_types = params[:production][:show_upcoming_event_types]

        # If checkboxes section was NOT rendered (first time switching to specific mode),
        # the key won't exist. If it exists (even as empty array with just ""), the section was rendered.
        checkboxes_were_rendered = params[:production].key?(:show_upcoming_event_types)

        if !checkboxes_were_rendered && @production.show_upcoming_event_types.blank?
          # First time switching to specific mode - initialize with defaults
          defaults = EventTypes.config.select { |_, config| config["public_visible_default"] }.keys
          params[:production][:show_upcoming_event_types] = defaults.to_json if defaults.any?
          return
        end

        # Checkboxes were rendered - process the submitted values
        if checkboxes_were_rendered
          event_types = event_types.reject(&:blank?) if event_types.is_a?(Array)
          params[:production][:show_upcoming_event_types] = event_types.present? ? event_types.to_json : "[]"
        end
      end
    end
  end
end
