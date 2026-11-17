# frozen_string_literal: true

module My
  # The contractor asks the organization about one of their contract's dates
  # (ContractDateRequests): move it, cancel it, add one, or a question. One
  # request, about one date, with one answer; nothing changes until the
  # organization changes the contract. Only the contractor asks: a contract
  # person reads the contract and nothing more.
  class ContractDateRequestsController < ApplicationController
    before_action :require_authentication
    before_action :set_contract
    before_action :set_date_request, only: %i[withdraw dismiss]

    # The form, loaded into the Request date/time change modal on My Contracts.
    def new
      @shows = ContractDateRequests.askable_shows(@contract).to_a
      @zone = zone
    end

    def create
      adding = params[:show_id].to_s == "new"
      show = adding ? nil : ContractDateRequests.askable_shows(@contract).find_by(id: params[:show_id])
      kind = adding ? "add" : params[:kind].to_s.presence_in(ContractDateRequest::KINDS - %w[add])
      if kind.nil? || (!adding && show.nil?)
        redirect_to my_contracts_path, alert: "Choose a date and what you need." and return
      end

      proposed_at = kind.in?(%w[move add]) ? parse_in_zone(params[:proposed_at]) : nil
      ContractDateRequests.ask!(contract: @contract, user: Current.user, show: show, kind: kind,
                                proposed_at: proposed_at, note: params[:note])
      notified = "#{@contract.organization.name} has been notified."
      redirect_to my_contracts_path, notice: kind == "question" ? notified : "#{notified} Nothing changes until they change the contract."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to my_contracts_path, alert: e.record.errors.full_messages.to_sentence
    rescue ContractDateRequests::NotAllowed
      redirect_to my_contracts_path, alert: "That date isn't available for a request."
    end

    def withdraw
      ContractDateRequests.withdraw!(@date_request, user: Current.user)
      redirect_to my_contracts_path, notice: "Request withdrawn."
    end

    def dismiss
      ContractDateRequests.dismiss!(@date_request, user: Current.user)
      redirect_to my_contracts_path
    end

    private

    # Only the contractor's own live contracts (the report-sales rule).
    def set_contract
      people_ids = Current.user.people.select(:id)
      @contract = Contract.joins(:contractor).where(contractors: { person_id: people_ids }).find_by(id: params[:id])
      return if @contract && ContractDateRequests.can_ask?(Current.user, @contract)

      redirect_to my_contracts_path, alert: "That contract isn't available."
    end

    def set_date_request
      @date_request = @contract.date_requests.find_by(id: params[:request_id])
      redirect_to my_contracts_path, alert: "That request isn't available." if @date_request.nil?
    end

    # The organization's own clock: the day and time asked for are read as
    # the venue would read them, wherever the contractor is.
    def zone
      Time.find_zone(@contract.organization.time_zone.presence) || Time.zone
    end

    def parse_in_zone(value)
      zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
