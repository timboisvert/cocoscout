# frozen_string_literal: true

module Manage
  module Staffing
    # CRUD for reusable employee/staff agreement templates. The list lives on the
    # Staffing Settings page; this controller owns the new/edit form pages and
    # mutations, redirecting back to Settings. Mirrors ContractTemplatesController.
    class AgreementTemplatesController < Manage::ManageController
      before_action :set_agreement_template, only: %i[edit update destroy preview]

      def new
        @agreement_template = Current.organization.staff_agreement_templates.build
        @agreement_template.content = StaffAgreementTemplateDefaults::DEFAULT_CONTENT
      end

      def create
        @agreement_template = Current.organization.staff_agreement_templates.build(agreement_template_params)

        if @agreement_template.save
          redirect_to manage_staffing_settings_path, notice: "Staff agreement created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @agreement_template.update(agreement_template_params)
          redirect_to manage_staffing_settings_path, notice: "Staff agreement updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @agreement_template.organization_staff_members.any?
          redirect_to manage_staffing_settings_path,
                      alert: "Can't delete an agreement that staff members are assigned to."
        else
          @agreement_template.destroy
          redirect_to manage_staffing_settings_path, notice: "Staff agreement deleted."
        end
      end

      def preview
        @rendered_content = @agreement_template.render_content(
          staff_name: "Jordan Rivera",
          organization_name: Current.organization.name,
          title: "Bartender",
          department: "Front of House",
          start_date: Date.current.strftime("%B %-d, %Y"),
          current_date: Date.current.strftime("%B %-d, %Y")
        )
      end

      private

      def set_agreement_template
        @agreement_template = Current.organization.staff_agreement_templates.find(params[:id])
      end

      def agreement_template_params
        params.require(:staff_agreement_template).permit(:name, :description, :content, :active)
      end
    end
  end
end
