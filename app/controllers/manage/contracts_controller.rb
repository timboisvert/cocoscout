# frozen_string_literal: true

module Manage
  class ContractsController < ManageController
    before_action :set_contract, except: %i[index new create]

    def index
      @contracts = Current.organization.contracts.order(created_at: :desc)

      @active_contracts = @contracts.status_active
      @draft_contracts = @contracts.status_draft
      @completed_contracts = @contracts.status_completed.or(@contracts.status_cancelled)

      # Upcoming payments for the dashboard alert
      @upcoming_payments = ContractPayment
        .joins(:contract)
        .where(contracts: { organization_id: Current.organization.id, status: "active" })
        .where(status: "pending")
        .where("due_date <= ?", 14.days.from_now)
        .order(:due_date)
    end

    def show
      # Draft contracts should be edited via the wizard
      if @contract.status_draft?
        redirect_to manage_contractor_contract_wizard_path(@contract) and return
      end

      @payments = @contract.contract_payments.by_due_date
      @documents = @contract.contract_documents.recent
      @rentals = @contract.space_rentals.includes(:location_space).order(:starts_at)
      @productions = @contract.productions.includes(:shows)
    end

    def new
      @contract = Current.organization.contracts.build
    end

    def create
      @contract = Current.organization.contracts.build(contract_params)

      if @contract.save
        redirect_to contractor_contract_wizard_path(@contract), notice: "Contract draft created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @contract.update(contract_params)
        redirect_to manage_contract_path(@contract), notice: "Contract updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @contract.destroy
      redirect_to manage_contracts_path, notice: "Contract deleted."
    end

    def activate
      if @contract.activate!
        redirect_to manage_contract_path(@contract), notice: "Contract activated. Productions and shows have been created."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not activate contract: #{@contract.errors.full_messages.join(', ')}"
      end
    end

    def complete
      if @contract.complete!
        redirect_to manage_contract_path(@contract), notice: "Contract marked as completed."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not complete contract."
      end
    end

    def cancel
      delete_events = params[:delete_events] == "true"

      if @contract.cancel!(delete_events: delete_events)
        notice = delete_events ? "Contract cancelled and events deleted." : "Contract cancelled. Events marked as cancelled."
        redirect_to manage_contracts_path, notice: notice
      else
        redirect_to manage_contract_path(@contract), alert: "Could not cancel contract."
      end
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:id])
    end

    def contract_params
      params.require(:contract).permit(
        :contractor_name, :contractor_email, :contractor_phone, :contractor_address,
        :contract_start_date, :contract_end_date, :notes, :terms
      )
    end
  end
end
