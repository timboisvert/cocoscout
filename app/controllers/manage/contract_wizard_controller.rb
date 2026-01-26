# frozen_string_literal: true

module Manage
  class ContractWizardController < ManageController
    before_action :set_contract, except: %i[new create_draft]

    # Step 0: Start new contract
    def new
      @contract = Current.organization.contracts.build
    end

    def create_draft
      @contract = Current.organization.contracts.build(
        contractor_name: params[:contract][:contractor_name].presence || "New Contract",
        status: :draft
      )

      if @contract.save
        redirect_to manage_contractor_contract_wizard_path(@contract)
      else
        render :new, status: :unprocessable_entity
      end
    end

    # Step 1: Contractor info
    def contractor
      @step = 1
    end

    def save_contractor
      if @contract.update(contractor_params)
        redirect_to manage_bookings_contract_wizard_path(@contract)
      else
        @step = 1
        render :contractor, status: :unprocessable_entity
      end
    end

    # Step 2: Bookings (space/time reservations)
    def bookings
      @step = 2
      @locations = Current.organization.locations.includes(:location_spaces)
      @existing_bookings = @contract.draft_bookings
    end

    def save_bookings
      bookings_data = params[:bookings].present? ? JSON.parse(params[:bookings]) : []
      @contract.update_draft_step(:bookings, bookings_data)
      redirect_to manage_services_contract_wizard_path(@contract)
    end

    # Step 3: Services included
    def services
      @step = 3
      @existing_services = @contract.draft_services
    end

    def save_services
      services_data = params[:services].present? ? JSON.parse(params[:services]) : []
      @contract.update_draft_step(:services, services_data)
      redirect_to manage_payments_contract_wizard_path(@contract)
    end

    # Step 4: Payment schedule
    def payments
      @step = 4
      @existing_payments = @contract.draft_payments
    end

    def save_payments
      payments_data = params[:payments].present? ? JSON.parse(params[:payments]) : []
      @contract.update_draft_step(:payments, payments_data)
      redirect_to manage_terms_contract_wizard_path(@contract)
    end

    # Step 5: Terms and notes
    def terms
      @step = 5
    end

    def save_terms
      if @contract.update(terms_params)
        redirect_to manage_review_contract_wizard_path(@contract)
      else
        @step = 5
        render :terms, status: :unprocessable_entity
      end
    end

    # Step 6: Review and activate
    def review
      @step = 6
      @valid_for_activation = @contract.valid_for_activation?
      @validation_errors = @contract.errors.full_messages unless @valid_for_activation
    end

    def activate
      if @contract.activate!
        redirect_to manage_contract_path(@contract), notice: "Contract activated successfully!"
      else
        @step = 6
        @valid_for_activation = false
        @validation_errors = @contract.errors.full_messages
        render :review, status: :unprocessable_entity
      end
    end

    def cancel
      @contract.destroy if @contract.status_draft?
      redirect_to manage_contracts_path, notice: "Contract draft discarded."
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end

    def contractor_params
      params.require(:contract).permit(
        :contractor_name, :contractor_email, :contractor_phone, :contractor_address
      )
    end

    def terms_params
      params.require(:contract).permit(
        :contract_start_date, :contract_end_date, :terms, :notes
      )
    end
  end
end
