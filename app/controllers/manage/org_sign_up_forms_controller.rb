# frozen_string_literal: true

module Manage
  class OrgSignUpFormsController < Manage::ManageController
    def index
      @filter = params[:filter] # 'registrations' or 'waitlists'

      # Get all in-house productions for the organization (exclude third-party)
      @productions = Current.organization.productions.type_in_house.includes(:sign_up_forms).order(:name)

      # Get all sign-up forms across all productions
      @all_sign_up_forms = SignUpForm.where(production: @productions)
                                      .not_archived
                                      .includes(:production, :sign_up_form_instances, :sign_up_slots)
                                      .order(created_at: :desc)

      # Apply filter if provided
      if @filter == "registrations"
        # Event registrations = single_event or repeated scope (not shared_pool/waitlists)
        @sign_up_forms = @all_sign_up_forms.where(scope: %w[single_event repeated])
        @page_title = "Event Registrations"
        @page_description = "Sign-up forms tied to specific events across all productions."
      elsif @filter == "waitlists"
        # Waitlists = shared_pool scope
        @sign_up_forms = @all_sign_up_forms.where(scope: "shared_pool")
        @page_title = "Waitlists"
        @page_description = "Waitlist forms not tied to specific events across all productions."
      else
        @sign_up_forms = @all_sign_up_forms
        @page_title = "All Sign-up Forms"
        @page_description = "All sign-up forms across all productions."
      end

      # Group by production for display
      @forms_by_production = @sign_up_forms.group_by(&:production)
    end
  end
end
