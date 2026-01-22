# frozen_string_literal: true

module Manage
  class OrgAuditionsController < Manage::ManageController
    def index
      @filter = params[:filter] # 'in_person' or 'video'

      # Get all productions for the organization
      @productions = Current.organization.productions.includes(:audition_cycles).order(:name)

      # Get all active audition cycles across all productions
      @all_active_cycles = AuditionCycle.where(production: @productions, active: true)
                                         .includes(:production, :audition_requests, :audition_sessions)
                                         .order(created_at: :desc)

      # Get all archived audition cycles
      @all_archived_cycles = AuditionCycle.where(production: @productions, active: false)
                                           .includes(:production)
                                           .order(created_at: :desc)

      # Apply filter if provided
      if @filter == "in_person"
        @cycles = @all_active_cycles.where(allow_in_person_auditions: true)
        @archived_cycles = @all_archived_cycles.where(allow_in_person_auditions: true)
      elsif @filter == "video"
        @cycles = @all_active_cycles.where(allow_video_submissions: true, allow_in_person_auditions: false)
        @archived_cycles = @all_archived_cycles.where(allow_video_submissions: true, allow_in_person_auditions: false)
      else
        @cycles = @all_active_cycles
        @archived_cycles = @all_archived_cycles
      end
    end
  end
end
