# frozen_string_literal: true

module Manage
  class CocobaseFieldsController < Manage::ManageController
    before_action :require_superadmin
    before_action :set_production
    before_action :check_production_access
    before_action :set_show
    before_action :set_cocobase
    before_action :set_field, only: [ :update, :destroy ]

    def create
      @field = @cocobase.cocobase_fields.new(field_params)
      @field.position = (@cocobase.cocobase_fields.maximum(:position) || -1) + 1

      if @field.save
        redirect_to manage_show_cocobase_path(@production, @show),
                    notice: "Field added successfully."
      else
        redirect_to manage_show_cocobase_path(@production, @show),
                    alert: @field.errors.full_messages.join(", ")
      end
    end

    def update
      if @field.update(field_params)
        redirect_to manage_show_cocobase_path(@production, @show),
                    notice: "Field updated."
      else
        redirect_to manage_show_cocobase_path(@production, @show),
                    alert: @field.errors.full_messages.join(", ")
      end
    end

    def destroy
      @field.destroy
      redirect_to manage_show_cocobase_path(@production, @show),
                  notice: "Field removed."
    end

    def reorder
      positions = params[:positions]
      return head :bad_request unless positions.is_a?(Array)

      positions.each_with_index do |id, index|
        @cocobase.cocobase_fields.where(id: id).update_all(position: index)
      end

      head :ok
    end

    private

    def set_production
      @production = Current.organization.productions.find(params[:production_id])
      sync_current_production(@production)
    end

    def set_show
      @show = @production.shows.find(params[:show_id])
    end

    def set_cocobase
      @cocobase = @show.cocobase
      unless @cocobase
        redirect_to manage_production_show_path(@production, @show),
                    alert: "No Cocobase exists for this show."
      end
    end

    def set_field
      @field = @cocobase.cocobase_fields.find(params[:id])
    end

    def field_params
      params.require(:cocobase_field).permit(:label, :description, :field_type, :required)
    end
  end
end
