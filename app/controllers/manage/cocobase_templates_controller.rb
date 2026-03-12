# frozen_string_literal: true

module Manage
  class CocobaseTemplatesController < Manage::ManageController
    before_action :require_superadmin
    before_action :set_production
    before_action :check_production_access

    def show
      @template = @production.cocobase_template || @production.build_cocobase_template
      @fields = @template.persisted? ? @template.cocobase_template_fields.order(:position) : []
      @event_types = EventTypes.all
    end

    def update
      @template = @production.cocobase_template || @production.build_cocobase_template

      @template.assign_attributes(template_params)

      if @template.save
        redirect_to manage_casting_cocobase_template_path(@production),
                    notice: "Cocobase template updated successfully."
      else
        @fields = @template.persisted? ? @template.cocobase_template_fields.order(:position) : []
        @event_types = EventTypes.all
        flash.now[:alert] = @template.errors.full_messages.join(", ")
        render :show, status: :unprocessable_entity
      end
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def template_params
      permitted = params.require(:cocobase_template).permit(:enabled, :default_deadline_days, event_types: [])
      # Filter out blank event_types values from form checkboxes
      permitted[:event_types] = permitted[:event_types]&.reject(&:blank?) || []
      permitted
    end
  end
end
