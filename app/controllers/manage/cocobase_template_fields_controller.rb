# frozen_string_literal: true

module Manage
  class CocobaseTemplateFieldsController < Manage::ManageController
    before_action :require_superadmin
    before_action :set_production
    before_action :check_production_access
    before_action :set_template
    before_action :set_field, only: [ :update, :destroy ]

    def create
      @field = @template.cocobase_template_fields.new(field_params)
      @field.position = (@template.cocobase_template_fields.maximum(:position) || -1) + 1

      if @field.save
        redirect_to manage_casting_cocobase_template_path(@production),
                    notice: "Field added successfully."
      else
        redirect_to manage_casting_cocobase_template_path(@production),
                    alert: @field.errors.full_messages.join(", ")
      end
    end

    def update
      if @field.update(field_params)
        redirect_to manage_casting_cocobase_template_path(@production),
                    notice: "Field updated."
      else
        redirect_to manage_casting_cocobase_template_path(@production),
                    alert: @field.errors.full_messages.join(", ")
      end
    end

    def destroy
      @field.destroy
      redirect_to manage_casting_cocobase_template_path(@production),
                  notice: "Field removed."
    end

    def reorder
      positions = params[:positions]
      return head :bad_request unless positions.is_a?(Array)

      positions.each_with_index do |id, index|
        @template.cocobase_template_fields.where(id: id).update_all(position: index)
      end

      head :ok
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_template
      @template = @production.cocobase_template
      unless @template
        redirect_to manage_casting_cocobase_template_path(@production),
                    alert: "Please save template settings first."
      end
    end

    def set_field
      @field = @template.cocobase_template_fields.find(params[:id])
    end

    def field_params
      params.permit(:label, :description, :field_type, :required)
    end
  end
end
