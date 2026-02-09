# frozen_string_literal: true

module Manage
  class SignupsController < Manage::ManageController
    before_action :set_production, except: [ :org_index ]
    before_action :check_production_access, except: [ :org_index ]
    before_action :check_not_third_party, except: [ :org_index ]

    # GET /signups (org-wide)
    def org_index
      # Get in-house productions the user has access to (exclude third-party)
      @productions = Current.user.accessible_productions.type_in_house.includes(:audition_cycles, :sign_up_forms).order(:name)

      # Aggregate sign-up forms and audition cycles across all productions
      @all_sign_up_forms = SignUpForm.where(production: @productions).not_archived.includes(:production, :sign_up_form_instances, :sign_up_slots)

      # "Active" means: open now, scheduled to open, or has future events
      @active_sign_up_forms = @all_sign_up_forms.select do |f|
        status = f.current_status
        status[:accepting_registrations] ||
          status[:state] == :scheduled ||
          status[:next_event].present?
      end

      # Audition cycles across all productions
      @all_active_audition_cycles = AuditionCycle.where(production: @productions, active: true).includes(:production, :audition_requests)
      @all_past_audition_cycles = AuditionCycle.where(production: @productions, active: false).includes(:production)

      # Build per-production summaries
      @production_summaries = @productions.map do |production|
        sign_up_forms = @all_sign_up_forms.select { |f| f.production_id == production.id }
        # Same "active" definition per production
        active_forms = sign_up_forms.select do |f|
          status = f.current_status
          status[:accepting_registrations] ||
            status[:state] == :scheduled ||
            status[:next_event].present?
        end
        active_audition_cycle = @all_active_audition_cycles.find { |c| c.production_id == production.id }
        past_audition_cycles = @all_past_audition_cycles.select { |c| c.production_id == production.id }

        {
          production: production,
          sign_up_forms_count: sign_up_forms.count,
          active_sign_up_forms_count: active_forms.count,
          active_audition_cycle: active_audition_cycle,
          audition_requests_count: active_audition_cycle&.audition_requests&.count || 0,
          past_audition_cycles_count: past_audition_cycles.count
        }
      end
    end

    # GET /signups/:production_id (production-level)
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
