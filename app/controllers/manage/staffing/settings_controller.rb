# frozen_string_literal: true

module Manage
  module Staffing
    # Org-level staffing settings. Today this is the employee agreement (the terms
    # staff agree to during onboarding); the agreement-template CRUD lives in
    # AgreementTemplatesController and redirects back here. Mirrors
    # Manage::ContractSettingsController's "templates" section.
    class SettingsController < Manage::ManageController
      def show
        @agreement_templates = Current.organization.staff_agreement_templates.order(:name)
      end

      # Declare whether staff must sign an agreement — and which one. Blank clears
      # the requirement. We only accept a template that belongs to this org.
      def update
        template_id = params[:required_staff_agreement_template_id].presence
        template = template_id && Current.organization.staff_agreement_templates.find_by(id: template_id)

        Current.organization.update!(required_staff_agreement_template: template)
        redirect_to manage_staffing_settings_path,
                    notice: if template
                              "Staff are now required to sign “#{template.name}.”"
                            else
                              "Staff are no longer required to sign an agreement."
                            end
      end
    end
  end
end
