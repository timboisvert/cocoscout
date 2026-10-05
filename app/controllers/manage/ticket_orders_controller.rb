# frozen_string_literal: true

module Manage
  # Every ticket order: find one by name, email or code, see what was paid
  # and where it went, resend the tickets, refund some or all of it, or move
  # them to another date. A refund or a move is reviewed on its own page
  # (what happens to the tickets and the money) before it happens.
  class TicketOrdersController < Manage::TicketingBaseController
    STATUS_FILTERS = %w[paid refunded].freeze

    before_action :set_order, except: :index

    def index
      @listings = Current.organization.ticket_listings.joins(:show).includes(:show, :production)
                         .order("shows.date_and_time DESC").limit(200)
      scope = Current.organization.ticket_orders.where(status: TicketOrder::WAS_PAID)
                     .includes(:tickets, ticket_listing: %i[show production]).order(paid_at: :desc, id: :desc)
      @listing = Current.organization.ticket_listings.find_by(id: params[:listing_id]) if params[:listing_id].present?
      scope = scope.where(ticket_listing: @listing) if @listing
      @production = Current.organization.productions.find_by(id: params[:production_id]) if params[:production_id].present? && !@listing
      scope = scope.where(ticket_listing_id: Current.organization.ticket_listings.where(production: @production).select(:id)) if @production
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
      @items = @order.ticket_order_items.includes(:fulfilled_by).order(:id).to_a
      @refunds = @order.ticket_refunds.order(:created_at).includes(:refunded_by).to_a
      @refundable_ids = TicketOrderRefund.refundable(@order).pluck(:id)
      @refundable_item_ids = TicketOrderRefund.refundable_items(@order).pluck(:id)
      @refunds_allowed = TicketOrderRefund.allowed?(@order)
      @disputed = TicketDispute.open?(@order)
      @exchanges_out = @order.exchanges_out.includes(to_order: { ticket_listing: :show }).order(:id).to_a
      @movable = @order.paid? && @order.money_path.in?(%w[cocoscout none]) && @refunds_allowed &&
                 TicketOrderExchange.movable(@order).exists?
    end

    # Moving tickets to another date of the same production: the date, the
    # tickets, and what each ticket type becomes, with what happens to the
    # money, before anything moves.
    def exchange_review
      @movable = TicketOrderExchange.movable(@order).to_a
      if @movable.empty?
        redirect_to manage_ticket_order_path(@order.id), alert: "None of these tickets can move." and return
      end

      @targets = TicketOrderExchange.targets(@order).to_a
      @target = @targets.find { |listing| listing.id == params[:to_listing_id].to_i }
      @ticket_ids = params[:picked] ? Array(params[:ticket_ids]).compact_blank.map(&:to_i) : @movable.map(&:id)
      chosen = @movable.select { |ticket| @ticket_ids.include?(ticket.id) }
      @tier_map = @target ? TicketOrderExchange.tier_map(chosen, @target, tier_params) : {}
      return unless @target

      if chosen.empty?
        @problem = "Choose the tickets to move."
      else
        @plan = TicketOrderExchange.plan(@order, target: @target, ticket_ids: @ticket_ids, chosen_tiers: tier_params)
      end
    rescue TicketOrderExchange::Error => e
      @problem = e.message
    end

    def exchange
      target = TicketOrderExchange.targets(@order).find_by(id: params[:to_listing_id])
      ticket_ids = Array(params[:ticket_ids]).compact_blank
      raise TicketOrderExchange::Error, "Choose the tickets to move." if ticket_ids.empty?

      exchange = TicketOrderExchange.exchange!(@order, target: target, ticket_ids: ticket_ids, chosen_tiers: tier_params,
                                                       by: Current.user, email_them: params[:email_them] == "1")
      moved = helpers.pluralize(exchange.ticket_ids.size, "ticket")
      notice = "Moved #{moved} to #{target.show.date_and_time.strftime('%A, %B %-d')}."
      notice += " Refunded the #{helpers.number_to_currency(exchange.difference_cents / 100.0)} difference." if exchange.ticket_refund
      alert = "The #{helpers.number_to_currency(exchange.difference_cents / 100.0)} refund didn't go through: #{exchange.refund_error}" if exchange.refund_error
      redirect_to manage_ticket_order_path(exchange.to_order_id), notice: notice, alert: alert
    rescue TicketOrderExchange::Error => e
      redirect_to manage_ticket_order_exchange_path(@order.id, to_listing_id: params[:to_listing_id]), alert: e.message
    end

    # What a refund of the chosen tickets gives back, before it happens.
    def refund_review
      unless TicketOrderRefund.allowed?(@order)
        redirect_to manage_ticket_order_path(@order.id), alert: "Refunds after the show are off. You can turn them on in Ticketing settings." and return
      end

      @keep_fees = params[:keep_fees] == "1"
      @quote = TicketOrderRefund.quote(@order, ticket_ids: chosen_ticket_ids, item_ids: chosen_item_ids, keep_fees: @keep_fees)
      if @quote.empty?
        redirect_to manage_ticket_order_path(@order.id), alert: "Choose the tickets to refund." and return
      end

      listing = @order.ticket_listing
      @available_cents = CocoScoutBalance.available_cents(Current.organization)
      @short = @order.money_path == "cocoscout" && listing.released_at.present? && @quote.org_debit_cents > @available_cents
      @short_cents = CocoScoutBalance.shortfall_cents(Current.organization, @quote.org_debit_cents) if @short
    end

    def refund
      refund = TicketOrderRefund.issue!(@order, ticket_ids: chosen_ticket_ids, item_ids: chosen_item_ids, keep_fees: params[:keep_fees] == "1",
                                                by: Current.user, reason: params[:reason].presence)
      notice = if @order.money_path == "none"
        "Canceled #{helpers.pluralize(refund.ticket_ids.size, 'ticket')} for #{@order.buyer_name.presence || 'the guest'}. The seats are free again."
      elsif @order.money_path == "cash"
        "Refunded #{helpers.number_to_currency(refund.amount_cents / 100.0)}: hand it back from the cash box."
      else
        "Refunded #{helpers.number_to_currency(refund.amount_cents / 100.0)} to #{@order.buyer_name.presence || 'the buyer'}."
      end
      redirect_to manage_ticket_order_path(@order.id), notice: notice
    rescue TicketOrderRefund::Error => e
      redirect_to manage_ticket_order_path(@order.id), alert: e.message
    end

    # The balance can't cover a refund after the show: add the difference
    # from the bank, and the refund goes out the moment it lands (at once
    # by card; in a few days by bank debit).
    def refund_top_up
      keep_fees = params[:keep_fees] == "1"
      quote = TicketOrderRefund.quote(@order, ticket_ids: chosen_ticket_ids, item_ids: chosen_item_ids, keep_fees: keep_fees)
      short = CocoScoutBalance.shortfall_cents(Current.organization, quote.org_debit_cents)
      unless short.positive?
        redirect_to manage_ticket_order_refund_path(@order.id, ticket_ids: params[:ticket_ids], item_ids: params[:item_ids], keep_fees: params[:keep_fees]) and return
      end

      top_up = BalanceTopUpService.start!(Current.organization, amount_cents: short, by: Current.user, refund_request: {
        "order_id" => @order.id, "ticket_ids" => quote.tickets.map(&:id), "item_ids" => quote.items.map(&:id), "keep_fees" => keep_fees,
        "reason" => params[:reason].presence, "user_id" => Current.user.id
      })
      notice = if top_up.status == "succeeded"
        "Added #{helpers.number_to_currency(short / 100.0)} and refunded #{@order.buyer_name.presence || 'the buyer'}."
      else
        "Adding #{helpers.number_to_currency(short / 100.0)} from your bank. The refund goes out when it lands, in 2 to 4 business days."
      end
      redirect_to manage_ticket_order_path(@order.id), notice: notice
    rescue BalanceTopUpService::Error => e
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

    # { old ticket type id => chosen new one } from the move form.
    def tier_params
      tiers = params[:tiers]
      tiers.respond_to?(:each_pair) ? tiers.each_pair.to_h { |from, to| [ from.to_i, to.to_s ] } : {}
    end

    def set_order
      @order = Current.organization.ticket_orders.includes(ticket_listing: %i[show production]).find(params[:id])
    end

    # The tickets and product lines ticked on the order page: nil when the
    # form carried no such boxes at all (they all go, a whole-order refund),
    # [] when it did and none were ticked.
    def chosen_ticket_ids
      params.key?(:ticket_ids) ? Array(params[:ticket_ids]).compact_blank : nil
    end

    def chosen_item_ids
      params.key?(:item_ids) ? Array(params[:item_ids]).compact_blank : nil
    end
  end
end
