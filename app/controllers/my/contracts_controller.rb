# frozen_string_literal: true

module My
  # Talent-side "My Contracts" — the contracts a signed-in person is on, as
  # the contractor (the Person backing a Contractor: signs, is paid, reports
  # sales) or as one of the people on it (ContractPerson,
  # docs/contract_people_plan.md: the contractor's visibility, nothing to pay
  # or sign), with their terms and, for the contractor, how to get paid.
  class ContractsController < ApplicationController
    before_action :require_authentication
    before_action :set_reportable_contract, only: [ :report_sales, :save_sales_report ]

    def index
      @show_my_sidebar = true
      @contracts = my_contracts.to_a
      # Make sure executed contracts have their signed PDF generated (idempotent).
      @contracts.each(&:ensure_signed_pdf!)
      # The contracts they're the contractor on: the ones with money to receive or pay.
      @people_ids = person_ids.map(&:id)
      @payee_contract_ids = @contracts.select { |contract| contract.payee_among?(@people_ids) }.map(&:id).to_set
      # Whether they still need to connect a bank to be paid: only when a
      # contract has something to pay them (Tim, 2026-11-17: the panel showed
      # on a contract where they pay the organization). The organizations
      # that would pay are named on it.
      @paying_organizations = if @payee_contract_ids.any?
        Organization.where(id: Contract.where(id: @payee_contract_ids.to_a)
                                       .where(id: ContractPayment.where(direction: "outgoing").where.not(status: %w[cancelled paid]).select(:contract_id))
                                       .select(:organization_id)).order(:name).pluck(:name)
      else
        []
      end
      @needs_bank = @paying_organizations.any? && Current.user.people.select(&:can_receive_payouts?).empty?
      # Live ticket sales for the contracts' upcoming shows, when the theater
      # sells them on CocoScout and shares the numbers (TicketSalesAccess).
      @ticket_sales = ticket_sales_by_contract
      # What the contractor has asked about each contract's dates, and where
      # each request stands (ContractDateRequests).
      @date_requests = ContractDateRequest.where(contract_id: @payee_contract_ids.to_a).showing_to_asker
                                          .includes(:show, :organization).order(:created_at).group_by(&:contract_id)
      # Each contract's connection to an organization of the contractor's own
      # (ContractConnections): the latest one, and whether one can be requested.
      @connections = ContractConnection.where(contract_id: @contracts.map(&:id)).includes(:linked_organization, :linked_production)
                                       .order(:created_at).index_by(&:contract_id)
      managed = ContractConnections.managed_organization_ids(Current.user)
      # A contract connected to an organization they run shows its ticket
      # numbers there, not here: the card points to it instead.
      @moved_contract_ids = @connections.values.select { |connection| connection.connected? && managed.include?(connection.linked_organization_id) }
                                        .map(&:contract_id).to_set
      @moved_contract_ids.each { |id| @ticket_sales[id] = [] }
      @connectable_contract_ids = @contracts.select do |contract|
        @payee_contract_ids.include?(contract.id) && contract.status_active? && !@connections[contract.id]&.live? &&
          (managed - [ contract.organization_id ]).any?
      end.map(&:id).to_set
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
          # The contractor reports one figure — they sell the tickets, and the
          # org's own ticket sources aren't their business. If the org had
          # already split this show by source, those lines would silently
          # overwrite what was just reported the next time one was touched, so
          # the report replaces them with the single line it represents.
          if financials.ticket_sales_lines.exists?
            financials.ticket_sales_lines.destroy_all
            financials.ticket_sales_lines.create!(tickets_sold: count.to_i, amount: revenue.to_f, position: 0)
          end
          ContractPaymentSyncService.new(show).call
          reported += 1
        end
      end

      redirect_to my_contracts_path,
                  notice: "Thanks — your ticket sales are in. #{@contract.organization.name} will bill you your share."
    end

    private

    # { contract_id => [[listing, stats], ...] } for upcoming dates, soonest first.
    def ticket_sales_by_contract
      visible = TicketSalesAccess.listings_for(Current.user).joins(:show).where("shows.date_and_time >= ?", Time.current.beginning_of_day)
                                 .includes(:show).order("shows.date_and_time").to_a
      return {} if visible.empty?

      stats = Ticketing::ListingStats.for(visible)
      @contracts.to_h do |contract|
        next [ contract.id, [] ] unless contract.shares_ticket_sales

        show_ids = contract.contract_shows.pluck(:id).to_set
        [ contract.id, visible.select { |l| show_ids.include?(l.show_id) }.first(4).map { |l| [ l, stats[l.id] ] } ]
      end
    end

    def my_contracts
      Contract.visible_to(Current.user)
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

    # { contract_id => [[listing, stats], ...] } for upcoming dates, soonest first.

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
