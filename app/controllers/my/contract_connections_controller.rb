# frozen_string_literal: true

module My
  # The contractor connects one of their contracts to an organization of
  # their own (ContractConnections; one show, two organizations). Four
  # steps, each a GET that carries the choices so far in its address: what
  # connecting does, which production takes the dates, how dates already
  # there line up with the contract's (LinkedDates), and what the other
  # side gets. The last one posts the request; the organization that wrote
  # the contract accepts or declines.
  class ContractConnectionsController < ApplicationController
    before_action :require_authentication
    before_action { @show_my_sidebar = true }
    before_action :set_contract
    before_action :require_requestable, only: %i[start production dates review create]
    before_action :set_choices, only: %i[dates review create]

    def start
      @shows = LinkedDates.contract_shows(@contract).to_a
      @standing_organization = @organizations.find { |organization| ContractConnections.standing_yes(@contract, organization: organization) }
    end

    # Which organization (when they run several) and which production.
    def production
      @organization = chosen_organization || @organizations.first
      @productions = @organization.productions.order(:name).to_a
      contract_name = @contract.production&.name.to_s
      @suggested = @productions.find { |production| production.name.casecmp?(contract_name) }
      @new_name = contract_name
      @can_make_new = !@organization.at_production_limit?
      @standing = ContractConnections.standing_yes(@contract, organization: @organization)
    end

    # How the dates already in their production line up with the contract's.
    # Nothing to check for a new production, or one with no shows of its own.
    def dates
      return redirect_to(my_connect_contract_review_path(@contract, carried)) if @production.nil?

      @comparison = LinkedDates.compare(@contract, @production)
      redirect_to my_connect_contract_review_path(@contract, carried) if @comparison.nothing_to_check?
    end

    def review
      @comparison = LinkedDates.compare(@contract, @production) if @production
      @standing = ContractConnections.standing_yes(@contract, organization: @organization)
      # The other people who manage it: they see the sales too.
      @managers = User.where(id: [ @organization.owner_id ] + @organization.organization_roles.where(company_role: "manager").pluck(:user_id))
                      .where.not(id: Current.user.id)
                      .filter_map { |user| user.default_person&.name || user.people.first&.name }.uniq
    end

    def create
      connection = ContractConnections.request!(contract: @contract, user: Current.user, organization: @organization, production: @production,
                                                new_production_name: @new_name, note: params[:note], date_answers: date_answers)
      org = @contract.organization.name
      notice = if connection.connected?
        "Your contract is now connected, and #{org} has been notified. You'll find their dates in #{connection.production_name}, in #{@organization.name}."
      else
        "Your request has been sent, and #{org} has been notified. Nothing will change until they accept."
      end
      redirect_to my_contracts_path, notice: notice
    rescue ActiveRecord::RecordInvalid => e
      redirect_to my_contracts_path, alert: e.record.errors.full_messages.to_sentence
    rescue ContractConnections::NotAllowed
      redirect_to my_contracts_path, alert: "That contract can't be connected right now."
    end

    # Take back a request nobody has answered.
    def withdraw
      connection = @contract.connections.requested.first
      if connection && ContractConnections.theirs?(connection, Current.user)
        ContractConnections.withdraw!(connection, user: Current.user)
        redirect_to my_contracts_path, notice: "Request withdrawn."
      else
        redirect_to my_contracts_path, alert: "There's no request to withdraw."
      end
    end

    # "Not now": the offer is put away, and stays as a quiet link on the
    # contract's card.
    def not_now
      ContractConnections.not_now!(@contract, user: Current.user)
      redirect_to my_contracts_path
    rescue ContractConnections::NotAllowed
      redirect_to my_contracts_path
    end

    # Clear an answer (declined, unlinked) from the contract's card.
    def dismiss
      @contract.connections.where(status: %w[declined unlinked], dismissed_at: nil).find_each do |connection|
        connection.update!(dismissed_at: Time.current) if ContractConnections.theirs?(connection, Current.user)
      end
      redirect_to my_contracts_path
    end

    private

    # Only the contractor's own contracts.
    def set_contract
      people_ids = Current.user.people.select(:id)
      @contract = Contract.joins(:contractor).where(contractors: { person_id: people_ids }).find_by(id: params[:id])
      redirect_to my_contracts_path, alert: "That contract isn't available." if @contract.nil?
    end

    def require_requestable
      @organizations = ContractConnections.organizations_for(Current.user, @contract).to_a
      return if ContractConnections.can_request?(Current.user, @contract)
      # The contractor who runs no organization yet still gets the first
      # page, which says what connecting does and how to start one.
      return if action_name == "start" && @organizations.empty? && ContractConnections.contractor?(Current.user, @contract) &&
                @contract.status_active? && @contract.connections.live.none?

      redirect_to my_contracts_path, alert: "That contract can't be connected right now."
    end

    def chosen_organization
      @organizations.find { |organization| organization.id == params[:organization_id].to_i }
    end

    # The organization and production chosen on the second step: an
    # existing production of theirs, or "new" with its name.
    def set_choices
      @organization = chosen_organization
      return redirect_to(my_connect_contract_production_path(@contract), alert: "Choose where the dates should go.") if @organization.nil?

      if params[:production].to_s == "new"
        @new_name = params[:new_name].to_s.strip.presence || @contract.production&.name
      else
        @production = @organization.productions.find_by(id: params[:production])
        redirect_to my_connect_contract_production_path(@contract, organization_id: @organization.id), alert: "Choose a production." if @production.nil?
      end
    end

    # What's carried from step to step.
    def carried
      params.permit(:organization_id, :production, :new_name, pair: {}, call: {}, join: {}).to_h
    end
    helper_method :carried

    # What they said about dates already in the production (LinkedDates).
    def date_answers
      return {} unless @production

      LinkedDates.answers_from(@contract, @production, pair: params[:pair], call: params[:call], join: params[:join])
    end
  end
end
