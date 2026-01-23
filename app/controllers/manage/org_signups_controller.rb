# frozen_string_literal: true

module Manage
  class OrgSignupsController < Manage::ManageController
    def index
      # Get all productions for the organization
      @productions = Current.organization.productions.includes(:audition_cycles, :sign_up_forms).order(:name)

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
  end
end
