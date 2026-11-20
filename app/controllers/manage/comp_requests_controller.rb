# frozen_string_literal: true

module Manage
  # A request for more comps on one date, decided by the organization's owners
  # and managers on the date's page in Ticketing (CompRequest; Tim,
  # 2026-11-20): approve it, approve a different number, or decline it, each
  # with an optional comment that goes back to whoever requested it in a
  # notification.
  class CompRequestsController < Manage::TicketingBaseController
    before_action :set_request

    def approve
      @request.approve!(by: Current.user, quantity: params[:quantity], comment: params[:comment])
      redirect_to back, notice: "Approved #{CompRequestNotices.more_comps(@request.approved_quantity)}. #{requester} has been notified."
    rescue CompRequest::Error => e
      redirect_to back, alert: e.message
    end

    def decline
      @request.decline!(by: Current.user, comment: params[:comment])
      redirect_to back, notice: "Declined. #{requester} has been notified."
    rescue CompRequest::Error => e
      redirect_to back, alert: e.message
    end

    private

    # Scoped to the current organization: never another organization's request.
    def set_request
      @request = CompRequest.where(organization: Current.organization).includes(ticket_listing: :show).find(params[:id])
    end

    def back = manage_ticket_listing_path(@request.ticket_listing)

    def requester = @request.requested_by.person&.name.presence || @request.requested_by.email_address
  end
end
