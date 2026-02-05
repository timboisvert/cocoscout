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
      # Fetch from SystemSetting, with hardcoded fallback
      SystemSetting.get("default_agreement_template") || <<~HTML.strip
        <div><strong>Performer Agreement for {{production_name}}</strong></div><div><br></div><div><strong>Code of Conduct</strong></div><div><br></div><div>As a performer with {{organization_name}}, I agree to:</div><div><br></div><ul><li>Treat all cast, crew, and staff with respect and professionalism</li><li>Arrive on time for all scheduled calls and performances</li><li>Communicate promptly about any conflicts or issues</li><li>Maintain a safe and inclusive environment for all</li><li>Follow all venue rules and policies</li></ul><div><br></div><div><strong>Attendance &amp; Communication</strong></div><div><br></div><ul><li>I will notify production management at least 48 hours in advance if I cannot make a scheduled performance</li><li>I will check CocoScout regularly for schedule updates and messages</li><li>I will respond to messages from production within 24 hours</li></ul><div><br></div><div><strong>Compensation</strong></div><div><br></div><div>[Add your payment terms here - e.g., payment schedule, rates, etc.]</div><div><br></div><div><strong>Acknowledgment</strong></div><div><br></div><div>By signing below, I acknowledge that I have read, understand, and agree to abide by this agreement for my participation in {{production_name}}.</div><div><br></div><div>Signed on {{current_date}} by {{performer_name}}.</div>
      HTML
    end
  end
end
