# frozen_string_literal: true

module Manage
  class CocobasesController < Manage::ManageController
    before_action :require_superadmin
    before_action :set_production
    before_action :check_production_access
    before_action :set_show
    before_action :set_cocobase

    def show
      @fields = @cocobase.cocobase_fields.order(:position)
      @submissions = @cocobase.cocobase_submissions
                              .includes(submittable: { profile_headshots: { image_attachment: :blob } })
                              .order(:status, :created_at)
      @summary = @cocobase.completion_summary
    end

    def edit
      @fields = @cocobase.cocobase_fields.order(:position)
    end

    def update
      if @cocobase.update(cocobase_params)
        redirect_to manage_show_cocobase_path(@production, @show),
                    notice: "Cocobase updated successfully."
      else
        @fields = @cocobase.cocobase_fields.order(:position)
        flash.now[:alert] = @cocobase.errors.full_messages.join(", ")
        render :edit, status: :unprocessable_entity
      end
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

    def cocobase_params
      params.require(:cocobase).permit(:deadline, :status)
    end
  end
end
