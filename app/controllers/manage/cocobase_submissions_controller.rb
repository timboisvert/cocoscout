# frozen_string_literal: true

module Manage
  class CocobaseSubmissionsController < Manage::ManageController
    before_action :require_superadmin
    before_action :set_production
    before_action :check_production_access
    before_action :set_show
    before_action :set_cocobase

    def index
      @submissions = @cocobase.cocobase_submissions
                              .includes(submittable: { profile_headshots: { image_attachment: :blob } })
                              .order(:status, :created_at)
      @fields = @cocobase.cocobase_fields.order(:position)
      @summary = @cocobase.completion_summary
    end

    def show
      @submission = @cocobase.cocobase_submissions
                             .includes(:cocobase_answers, submittable: { profile_headshots: { image_attachment: :blob } })
                             .find(params[:id])
      @fields = @cocobase.cocobase_fields.order(:position)
      @answers_by_field = @submission.cocobase_answers.index_by(&:cocobase_field_id)
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
  end
end
