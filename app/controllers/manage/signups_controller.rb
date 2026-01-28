# frozen_string_literal: true

module Manage
  class SignupsController < Manage::ManageController
    before_action :set_production
    before_action :check_production_access
    before_action :check_not_third_party

    def index
      # Sign-up forms stats
      @sign_up_forms = @production.sign_up_forms.not_archived
      @active_sign_up_forms = @sign_up_forms.select { |f| f.current_status[:accepting_registrations] }
      @sign_up_forms_count = @sign_up_forms.count

      # Audition stats
      @active_audition_cycle = @production.active_audition_cycle
      @audition_requests_count = @active_audition_cycle&.audition_requests&.count || 0
      @past_audition_cycles_count = @production.audition_cycles.where(active: false).count

      # Sign-up form wizard in progress?
      @sign_up_wizard_in_progress = Rails.cache.read("sign_up_wizard:#{Current.user.id}:#{@production.id}").present?

      # Audition wizard in progress?
      @audition_wizard_in_progress = session[:audition_wizard].present? && session[:audition_wizard][@production.id.to_s].present?
    end

    private

    def set_production
      unless Current.organization
        redirect_to select_organization_path, alert: "Please select an organization first."
        return
      end
      @production = Current.organization.productions.find(params.require(:production_id))
      sync_current_production(@production)
    end

    def check_not_third_party
      if @production.type_third_party?
        redirect_to manage_shows_path(@production), alert: "Sign-ups are not available for third-party productions"
      end
    end
  end
end
