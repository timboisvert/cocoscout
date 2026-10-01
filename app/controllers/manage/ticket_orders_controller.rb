# frozen_string_literal: true

module Manage
  # Every ticket order: find one by name, email or code, see what was paid
  # and where it went, resend the tickets, and refund some or all of it.
  # A refund is reviewed on its own page (what goes back, and from where)
  # before it happens.
  class TicketOrdersController < Manage::TicketingBaseController
    STATUS_FILTERS = %w[paid refunded].freeze

    before_action :set_order, except: :index

    def index
      @listings = Current.organization.ticket_listings.joins(:show).includes(:show, :production)
                         .order("shows.date_and_time DESC").limit(200)
      scope = Current.organization.ticket_orders.where(status: %w[paid partially_refunded refunded])
                     .includes(:tickets, ticket_listing: %i[show production]).order(paid_at: :desc, id: :desc)
      @listing = Current.organization.ticket_listings.find_by(id: params[:listing_id]) if params[:listing_id].present?
      scope = scope.where(ticket_listing: @listing) if @listing
      @status = params[:status].presence_in(STATUS_FILTERS)
      scope = scope.where(status: @status == "paid" ? %w[paid partially_refunded] : %w[refunded partially_refunded]) if @status
      @query = params[:q].to_s.strip
      if @query.present?
        like = "%#{TicketOrder.sanitize_sql_like(@query)}%"
        scope = scope.where("ticket_orders.code = :code OR ticket_orders.buyer_name ILIKE :like OR ticket_orders.buyer_email ILIKE :like",
                            code: @query.upcase, like: like)
      end
      @pagy, @orders = pagy(scope, limit: 50)
    end

    def show
      @tickets = @order.tickets.includes(:ticket_tier, :checked_in_by, :tax_lines).order(:id).to_a
      @refunds = @order.ticket_refunds.order(:created_at).includes(:refunded_by).to_a
      @refundable_ids = TicketOrderRefund.refundable(@order).pluck(:id)
      @disputed = TicketDispute.open?(@order)
    end

    # What a refund of the chosen tickets gives back, before it happens.
    def refund_review
      @keep_fees = params[:keep_fees] == "1"
      @quote = TicketOrderRefund.quote(@order, ticket_ids: Array(params[:ticket_ids]).compact_blank, keep_fees: @keep_fees)
      if @quote.tickets.empty?
        redirect_to manage_ticket_order_path(@order.id), alert: "Choose the tickets to refund." and return
      end

      listing = @order.ticket_listing
      @available_cents = TicketBalance.available_cents(Current.organization)
      @short = @order.money_path == "cocoscout" && listing.released_at.present? && @quote.org_debit_cents > @available_cents
    end

    def refund
      ticket_ids = Array(params[:ticket_ids]).compact_blank
      refund = TicketOrderRefund.issue!(@order, ticket_ids: ticket_ids, keep_fees: params[:keep_fees] == "1",
                                                by: Current.user, reason: params[:reason].presence)
      notice = if @order.money_path == "cash"
        "Refunded #{helpers.number_to_currency(refund.amount_cents / 100.0)}: hand it back from the cash box."
      else
        "Refunded #{helpers.number_to_currency(refund.amount_cents / 100.0)} to #{@order.buyer_name.presence || 'the buyer'}."
      end
      redirect_to manage_ticket_order_path(@order.id), notice: notice
    rescue TicketOrderRefund::Error => e
      redirect_to manage_ticket_order_path(@order.id), alert: e.message
    end

    def resend
      if @order.buyer_email.present? && @order.paid?
        TicketOrderConfirmationJob.perform_later(@order.id)
        redirect_to manage_ticket_order_path(@order.id), notice: "Tickets sent again to #{@order.buyer_email}."
      else
        redirect_to manage_ticket_order_path(@order.id), alert: "This order has no email address to send to."
      end
    end

    private

    def set_order
      @order = Current.organization.ticket_orders.includes(ticket_listing: %i[show production]).find(params[:id])
    end
  end
end
