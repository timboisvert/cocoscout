# frozen_string_literal: true

module My
  # Talent-side "My Contracts" — the contracts a signed-in contractor (a Person
  # backing a Contractor) holds, with their terms and how to get paid.
  class ContractsController < ApplicationController
    before_action :require_authentication
    before_action :set_reportable_contract, only: [ :report_sales, :save_sales_report ]

    def index
      @show_my_sidebar = true
      @contracts = my_contracts.to_a
      # Make sure executed contracts have their signed PDF generated (idempotent).
      @contracts.each(&:ensure_signed_pdf!)
      # Whether they still need to connect a bank to be paid.
      @needs_bank = Current.user.people.select(&:can_receive_payouts?).empty?
    end

    # Case 2: the contractor enters ticket sales for each show themselves. We
    # trust the numbers — no manager approval.
    def report_sales
      @show_my_sidebar = true
      @shows = reportable_shows
    end

    def save_sales_report
      reported = 0

      ActiveRecord::Base.transaction do
        reportable_shows.each do |show|
          row = sales_params[show.id.to_s]
          next if row.blank?

          count = row[:ticket_count].presence
          revenue = row[:ticket_revenue].presence
          next if count.nil? && revenue.nil?

          financials = show.show_financials || show.build_show_financials
          financials.update!(
            revenue_type: "ticket_sales",
            ticket_count: count.to_i,
            ticket_revenue: revenue.to_f,
            data_confirmed: true,
            contractor_reported_at: Time.current
          )
          ContractPaymentSyncService.new(show).call
          reported += 1
        end
      end

      redirect_to my_contracts_path,
                  notice: "Thanks — your ticket sales are in. #{@contract.organization.name} will bill you your share."
    end

    private

    def my_contracts
      Contract.joins(:contractor)
              .where(contractors: { person_id: person_ids })
              # Show real contracts (active/completed/etc.) and e-sign contracts that
              # have actually been sent to them — but not drafts the org is still
              # preparing (unsent / awaiting_send).
              .where("contracts.status != 'draft' OR contracts.signing_state = 'out_for_signature'")
              .includes(:contractor, :production, :organization, :contract_payments,
                        { contract_documents: { file_attachment: :blob } },
                        space_rentals: [ :location, :location_space ])
              .order(created_at: :desc)
    end

    def person_ids
      Current.user.people.select(:id)
    end

    # Only contracts the signed-in person actually holds, and only the Case-2
    # kind they're allowed to report on.
    def set_reportable_contract
      @contract = Contract.joins(:contractor)
                          .where(contractors: { person_id: person_ids })
                          .find_by(id: params[:id])

      if @contract.nil?
        redirect_to my_contracts_path, alert: "That contract isn't available." and return
      end

      unless @contract.contractor_reports_sales?
        redirect_to my_contracts_path, alert: "There's nothing to report on this contract." and return
      end
    end

    def reportable_shows
      @contract.contract_shows.includes(:show_financials).order(:date_and_time).to_a
    end

    def sales_params
      params.fetch(:financials, {}).permit!.to_h
    end
  end
end
