# frozen_string_literal: true

module Manage
  # Connections: other organizations' contracts connected to this one as the
  # contractor's own organization (ContractConnections). Each brings that
  # contract's dates into one of this organization's productions, with their
  # ticket sales read-only. Here: where each stands, who in this
  # organization sees the sales, any question left about a date, and Unlink.
  # Free, for owners and managers; it's a page (status and actions), not a
  # settings tab.
  class ConnectionsController < Manage::ManageController
    before_action :ensure_org_owner_or_manager
    before_action :set_connection, only: %i[update unlink answer_date]

    def index
      @connections = scope.where.not(status: %w[withdrawn declined])
                          .includes(:organization, :linked_production, :requested_by, contract: :production).order(created_at: :desc).to_a
    end

    # Who in this organization sees the ticket sales, below its owners and
    # managers: the box office's own three choices.
    def update
      if @connection.update(params.fetch(:connection, {}).permit(:team_manager_sales, :team_viewer_sales, :cast_sales))
        redirect_to manage_connections_path, notice: "Saved."
      else
        redirect_to manage_connections_path, alert: @connection.errors.full_messages.to_sentence
      end
    end

    def unlink
      ContractConnections.unlink!(@connection, user: Current.user)
      redirect_to manage_connections_path,
                  notice: "Unlinked from #{@connection.organization.name}. Its dates stay in #{@connection.production_name} as your own. #{@connection.organization.name} has been notified."
    end

    # A question left open when connecting: is this date of ours the same
    # show as theirs?
    def answer_date
      LinkedDates.resolve!(@connection, contract_show_id: params[:contract_show_id], show_id: params[:show_id], same: params[:same] == "1")
      redirect_to manage_connections_path, notice: (params[:same] == "1" ? "Treated as the same show. Its cast stays." : "Kept as two events.")
    rescue ArgumentError => e
      redirect_to manage_connections_path, alert: e.message
    end

    private

    # Only this organization's own: the ones where it is the contractor's side.
    def scope
      ContractConnection.where(linked_organization_id: Current.organization.id)
    end

    def set_connection
      @connection = scope.find(params[:id])
    end
  end
end
