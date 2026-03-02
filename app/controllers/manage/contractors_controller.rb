# frozen_string_literal: true

module Manage
  class ContractorsController < ManageController
    before_action :set_contractor, only: [ :show, :edit, :update, :destroy ]

    def index
      @contractors = Current.organization.contractors
        .includes(:contracts)
        .alphabetical

      @contractors_with_active = @contractors.select { |c| c.active_contracts.any? }
      @contractors_without_active = @contractors.reject { |c| c.active_contracts.any? }
    end

    def show
      @active_contracts = @contractor.contracts.status_active.order(:contract_start_date)
      @draft_contracts = @contractor.contracts.status_draft.order(:created_at)
      @completed_contracts = @contractor.contracts.status_completed
        .or(@contractor.contracts.status_cancelled)
        .order(contract_end_date: :desc)
    end

    def new
      @contractor = Current.organization.contractors.build
    end

    def create
      @contractor = Current.organization.contractors.build(contractor_params)

      if @contractor.save
        respond_to do |format|
          format.html { redirect_to manage_contractor_path(@contractor), notice: "Contractor created." }
          format.json do
            render json: {
              id: @contractor.id,
              name: @contractor.name,
              email: @contractor.email,
              phone: @contractor.phone,
              address: @contractor.address
            }, status: :created
          end
        end
      else
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: { errors: @contractor.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def edit
    end

    def update
      if @contractor.update(contractor_params)
        redirect_to manage_contractor_path(@contractor), notice: "Contractor updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @contractor.contracts.any?
        redirect_to manage_contractor_path(@contractor), alert: "Cannot delete contractor with existing contracts."
      else
        @contractor.destroy
        redirect_to manage_contractors_path, notice: "Contractor deleted."
      end
    end

    # JSON endpoint for autocomplete/search
    def search
      query = params[:q].to_s.strip
      contractors = Current.organization.contractors.alphabetical

      if query.present?
        contractors = contractors.where("LOWER(name) LIKE ?", "%#{query.downcase}%")
      end

      render json: contractors.limit(10).map { |c|
        {
          id: c.id,
          name: c.name,
          email: c.email,
          phone: c.phone,
          address: c.address,
          contracts_count: c.contracts.count
        }
      }
    end

    private

    def set_contractor
      @contractor = Current.organization.contractors.find(params[:id])
    end

    def contractor_params
      params.require(:contractor).permit(:name, :email, :phone, :address, :notes)
    end
  end
end
