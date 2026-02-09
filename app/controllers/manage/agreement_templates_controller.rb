# frozen_string_literal: true

module Manage
  class AgreementTemplatesController < ManageController
    before_action :set_organization
    before_action :set_agreement_template, only: %i[edit update destroy preview]

    def index
      @agreement_templates = @organization.agreement_templates.order(:name)
    end

    def new
      @agreement_template = @organization.agreement_templates.build
      @agreement_template.content = default_template_content
    end

    def create
      @agreement_template = @organization.agreement_templates.build(agreement_template_params)

      if @agreement_template.save
        redirect_to manage_agreement_templates_path, notice: "Agreement template created successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @agreement_template.update(agreement_template_params)
        redirect_to manage_agreement_templates_path, notice: "Agreement template updated successfully."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @agreement_template.productions.any?
        redirect_to manage_agreement_templates_path,
                    alert: "Cannot delete template that is in use by productions."
      else
        @agreement_template.destroy
        redirect_to manage_agreement_templates_path, notice: "Agreement template deleted."
      end
    end

    def preview
      @rendered_content = @agreement_template.render_content(
        production_name: "Example Production",
        organization_name: @organization.name,
        performer_name: "Jane Doe",
        current_date: Date.current.strftime("%B %-d, %Y")
      )
    end

    private

    def set_organization
      @organization = Current.organization
    end

    def set_agreement_template
      @agreement_template = @organization.agreement_templates.find(params[:id])
    end

    def agreement_template_params
      params.require(:agreement_template).permit(:name, :description, :content, :active)
    end

    def default_template_content
      SystemSetting.get("default_agreement_template") || AgreementTemplateDefaults::DEFAULT_CONTENT
    end
  end
end
