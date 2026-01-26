# frozen_string_literal: true

module Manage
  class SpaceRentalsController < ManageController
    before_action :set_contract
    before_action :set_rental, only: %i[update destroy]

    def create
      @rental = @contract.space_rentals.build(rental_params)

      if @rental.save
        redirect_to manage_contract_path(@contract), notice: "Rental booking added."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not add rental: #{@rental.errors.full_messages.join(', ')}"
      end
    end

    def update
      if @rental.update(rental_params)
        redirect_to manage_contract_path(@contract), notice: "Rental updated."
      else
        redirect_to manage_contract_path(@contract), alert: "Could not update rental: #{@rental.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @rental.destroy
      redirect_to manage_contract_path(@contract), notice: "Rental booking deleted."
    end

    private

    def set_contract
      @contract = Current.organization.contracts.find(params[:contract_id])
    end

    def set_rental
      @rental = @contract.space_rentals.find(params[:id])
    end

    def rental_params
      params.require(:space_rental).permit(
        :location_space_id, :starts_at, :ends_at, :notes, :confirmed
      )
    end
  end
end
