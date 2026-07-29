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
    end
  end
end
