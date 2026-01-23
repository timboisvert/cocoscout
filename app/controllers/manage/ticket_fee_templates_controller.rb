# frozen_string_literal: true

module Manage
  class TicketFeeTemplatesController < Manage::ManageController
    before_action :set_ticket_fee_template, only: [ :update, :destroy ]

    def index
      @ticket_fee_templates = Current.organization.ticket_fee_templates.default_first
    end

    def create
      @ticket_fee_template = Current.organization.ticket_fee_templates.build(ticket_fee_template_params)

      if @ticket_fee_template.save
        redirect_to manage_ticket_fee_templates_path, notice: "Fee template created."
      else
        @ticket_fee_templates = Current.organization.ticket_fee_templates.default_first
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @ticket_fee_template.update(ticket_fee_template_params)
        redirect_to manage_ticket_fee_templates_path, notice: "Fee template updated."
      else
        @ticket_fee_templates = Current.organization.ticket_fee_templates.default_first
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @ticket_fee_template.destroy
      redirect_to manage_ticket_fee_templates_path, notice: "Fee template deleted."
    end

    private

    def set_ticket_fee_template
      @ticket_fee_template = Current.organization.ticket_fee_templates.find(params[:id])
    end

    def ticket_fee_template_params
      params.require(:ticket_fee_template).permit(:name, :flat_per_ticket, :percentage, :is_default)
    end
  end
end
