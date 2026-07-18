# frozen_string_literal: true

module My
  # Talent-side "My Contracts" — the contracts a signed-in contractor (a Person
  # backing a Contractor) holds, with their terms and how to get paid.
  class ContractsController < ApplicationController
    before_action :require_authentication

    def index
      @show_my_sidebar = true
      person_ids = Current.user.people.select(:id)
      @contracts = Contract.joins(:contractor)
                           .where(contractors: { person_id: person_ids })
                           .includes(:contractor, :production, :organization, :contract_payments,
                                     :contract_documents, space_rentals: [ :location, :location_space ])
                           .order(created_at: :desc)
      # Whether they still need to connect a bank to be paid.
      @needs_bank = Current.user.people.select(&:can_receive_payouts?).empty?
    end
  end
end
