# frozen_string_literal: true

module Manage
  # CRUD for reusable contract-document templates. The list lives as the
  # "Templates" tab of Contract Settings; this controller owns the new/edit form
  # pages and mutations, redirecting back to that tab. Mirrors
  # AgreementTemplatesController.
  class ContractTemplatesController < ManageController
    before_action :set_contract_template, only: %i[edit update destroy preview]

    def new
      @contract_template = Current.organization.contract_templates.build
      @contract_template.content = ContractTemplateDefaults::DEFAULT_CONTENT
    end

    def create
      @contract_template = Current.organization.contract_templates.build(contract_template_params)

      if @contract_template.save
        redirect_to templates_section_path, notice: "Contract template created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @contract_template.update(contract_template_params)
        redirect_to templates_section_path, notice: "Contract template updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @contract_template.contracts.any?
        redirect_to templates_section_path,
                    alert: "Can't delete a template that's in use by contracts."
      else
        @contract_template.destroy
        redirect_to templates_section_path, notice: "Contract template deleted."
      end
    end

    def preview
      @rendered_content = @contract_template.render_content(
        contractor_name: "Local Comedy Troupe",
        organization_name: Current.organization.name,
        production_name: "Example Production",
        contract_start_date: Date.current.strftime("%B %-d, %Y"),
        contract_end_date: (Date.current + 3.months).strftime("%B %-d, %Y"),
        current_date: Date.current.strftime("%B %-d, %Y")
      )
    end

    private

    def set_contract_template
      @contract_template = Current.organization.contract_templates.find(params[:id])
    end

    def contract_template_params
      params.require(:contract_template).permit(:name, :description, :content, :active)
    end

    def templates_section_path
      manage_contract_settings_section_path(section: "templates")
    end
  end
end
