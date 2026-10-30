# frozen_string_literal: true

module Manage
  # Every ticket order: find one by name, email or code, see what was paid
  # and where it went, resend the tickets, refund some or all of it, or move
  # them to another date or ticket type. A refund or a move is reviewed on its own page
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
      # Refunds are always reviewable; the policy says whether one is within
      # it, and outside it the review asks for Refund anyway.
      @policy_check = TicketOrderRefund.policy_check(@order)
      @refunds_allowed = true
      @disputed = TicketDispute.open?(@order)
      @exchanges_out = @order.exchanges_out.includes(to_order: { ticket_listing: :show }).order(:id).to_a
      @movable = @order.paid? && @order.money_path.in?(%w[cocoscout none]) && @order.gift_certificate_cents.zero? && TicketOrderExchange.movable(@order).exists?
      # Everything ticked, fees as the policy has them: how the refund choices start.
      @refund_quote = TicketOrderRefund.quote(@order, keep_fees: !@policy_check.policy.fees) if @refundable_ids.any? || @refundable_item_ids.any?
    end

    # Moving tickets to another date of the same production, or to another
    # ticket type on their own date: the date, the tickets, and what each
    # ticket type becomes (types without room for them can't be picked), with
    # what happens to the money, before anything moves.
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

      @seats_left = TicketOrderExchange.seats_left(@target, chosen)
      @moving = chosen.group_by(&:ticket_tier_id).transform_values(&:size)

      # A show that has happened can still move, with Move anyway.
      @after_show = @order.ticket_listing.show.date_and_time <= Time.current
      if chosen.empty?
        @problem = "Choose the tickets to move."
      else
        @plan = TicketOrderExchange.plan(@order, target: @target, ticket_ids: @ticket_ids, chosen_tiers: tier_params, outside_policy: true)
      end
    rescue TicketOrderExchange::Error => e
      @problem = e.message
    end

    def exchange
      target = TicketOrderExchange.targets(@order).find_by(id: params[:to_listing_id])
      ticket_ids = Array(params[:ticket_ids]).compact_blank
      raise TicketOrderExchange::Error, "Choose the tickets to move." if ticket_ids.empty?

      exchange = TicketOrderExchange.exchange!(@order, target: target, ticket_ids: ticket_ids, chosen_tiers: tier_params,
                                                       by: Current.user, email_them: params[:email_them] == "1",
                                                       outside_policy: params[:outside_policy] == "1")
      moved = helpers.pluralize(exchange.ticket_ids.size, "ticket")
      notice = if target.id == @order.ticket_listing_id
        "Changed #{moved} to #{exchange.to_order.tickets.includes(:ticket_tier).map { |t| t.ticket_tier.name }.uniq.to_sentence}."
      else
        "Moved #{moved} to #{target.show.date_and_time.strftime('%A, %B %-d')}."
      end
      notice += " Refunded the #{helpers.number_to_currency(exchange.difference_cents / 100.0)} difference." if exchange.ticket_refund
      alert = "The #{helpers.number_to_currency(exchange.difference_cents / 100.0)} refund didn't go through: #{exchange.refund_error}" if exchange.refund_error
      redirect_to manage_ticket_order_path(exchange.to_order_id), notice: notice, alert: alert
    rescue TicketOrderExchange::Error => e
      redirect_to manage_ticket_order_exchange_path(@order.id, to_listing_id: params[:to_listing_id]), alert: e.message
    end

    # What a refund of the chosen tickets gives back, before it happens.
    def refund_review
      @check = TicketOrderRefund.policy_check(@order)
      # Whether the fees come back starts from the policy; the manager can change it.
      @keep_fees = params.key?(:keep_fees) ? params[:keep_fees] == "1" : !@check.policy.fees
      @reprice = reprice?
      @quote = TicketOrderRefund.quote(@order, ticket_ids: chosen_ticket_ids, item_ids: chosen_item_ids, keep_fees: @keep_fees, reprice: @reprice)
      if @quote.empty?
        redirect_to manage_ticket_order_path(@order.id), alert: "Choose the tickets to refund." and return
      end

      listing = @order.ticket_listing
      # The tax on these tickets is set aside for the government; refunding
      # gives it back to the buyer, so the refund can spend it.
      relief = SalesTaxSetAside.relief_cents(Current.organization, ticket_ids: @quote.tickets.map(&:id), item_ids: @quote.items.map(&:id))
      @available_cents = CocoScoutBalance.available_cents(Current.organization) + relief
      @short = @order.money_path == "cocoscout" && listing.released_at.present? && @quote.org_debit_cents > @available_cents
      @short_cents = CocoScoutBalance.shortfall_cents(Current.organization, @quote.org_debit_cents - relief) if @short
    end

    # What a refund comes to as the manager ticks tickets or keeps the fees on
    # the order page, before Review refund. Same quote as the review page.
    def refund_quote
      keep_fees = params.key?(:keep_fees) ? params[:keep_fees] == "1" : !TicketOrderRefund.policy_check(@order).policy.fees
      quote = TicketOrderRefund.quote(@order, ticket_ids: chosen_ticket_ids, item_ids: chosen_item_ids, keep_fees: keep_fees, reprice: reprice?)
      render json: refund_preview(quote)
    end

    def refund
      outside_policy = exception_allowed!
      # A canceled comp emails the guest unless the manager unticked it.
      refund = TicketOrderRefund.issue!(@order, ticket_ids: chosen_ticket_ids, item_ids: chosen_item_ids, keep_fees: params[:keep_fees] == "1",
                                                by: Current.user, reason: params[:reason].presence, buyer_message: params[:buyer_message].presence, reprice: reprice?,
                                                outside_policy: outside_policy, notify: params[:email_them] != "0")
      notice = if @order.money_path == "none"
        told = " and let #{@order.buyer_email} know" if params[:email_them] != "0" && @order.buyer_email.present?
        "Canceled #{helpers.pluralize(refund.ticket_ids.size, 'ticket')} for #{@order.buyer_name.presence || 'the guest'}#{told}. The seats are free again."
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
      outside_policy = exception_allowed!
      keep_fees = params[:keep_fees] == "1"
      quote = TicketOrderRefund.quote(@order, ticket_ids: chosen_ticket_ids, item_ids: chosen_item_ids, keep_fees: keep_fees, reprice: reprice?)
      relief = SalesTaxSetAside.relief_cents(Current.organization, ticket_ids: quote.tickets.map(&:id), item_ids: quote.items.map(&:id))
      short = CocoScoutBalance.shortfall_cents(Current.organization, quote.org_debit_cents - relief)
      unless short.positive?
        redirect_to manage_ticket_order_refund_path(@order.id, ticket_ids: params[:ticket_ids], item_ids: params[:item_ids], keep_fees: params[:keep_fees]) and return
      end

      top_up = BalanceTopUpService.start!(Current.organization, amount_cents: short, by: Current.user, refund_request: {
        "order_id" => @order.id, "ticket_ids" => quote.tickets.map(&:id), "item_ids" => quote.items.map(&:id), "keep_fees" => keep_fees,
        "reprice" => reprice?, "outside_policy" => outside_policy,
        "reason" => params[:reason].presence, "buyer_message" => params[:buyer_message].presence, "user_id" => Current.user.id
      })
      notice = if top_up.status == "succeeded"
        "Added #{helpers.number_to_currency(short / 100.0)} and refunded #{@order.buyer_name.presence || 'the buyer'}."
      else
        "Adding #{helpers.number_to_currency(short / 100.0)} from your bank. The refund goes out when it lands, in 2 to 4 business days."
      end
      redirect_to manage_ticket_order_path(@order.id), notice: notice
    rescue BalanceTopUpService::Error, TicketOrderRefund::Error => e
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

    # The buyer's email, corrected (a typo at checkout, or another inbox).
    # Other orders from the same checkout that had the same address change
    # with it, and when asked, the tickets go to the new address.
    def update_email
      email = params[:buyer_email].to_s.strip
      return redirect_to(manage_ticket_order_path(@order.id), alert: "Enter an email address.") if email.blank?

      orders = [ @order ]
      if @order.ticket_purchase && @order.buyer_email.present?
        orders |= @order.ticket_purchase.ticket_orders.where(buyer_email: @order.buyer_email).to_a
      end
      TicketOrder.transaction { orders.each { |order| order.update!(buyer_email: email) } }

      sent = params[:send_tickets] == "1" ? orders.select(&:paid?).each { |order| TicketOrderConfirmationJob.perform_later(order.id) } : []
      others = orders.size - 1
      notice = "Email changed to #{@order.buyer_email}"
      notice += " here and on #{helpers.pluralize(others, 'other order')} from the same checkout" if others.positive?
      notice += sent.any? ? ", and the tickets are on their way." : "."
      redirect_to manage_ticket_order_path(@order.id), notice: notice
    rescue ActiveRecord::RecordInvalid
      redirect_to manage_ticket_order_path(@order.id), alert: "\"#{email}\" isn't an email address. Nothing was changed."
    end

    private

    # The line the order page shows under the refund choices.
    def refund_preview(quote)
      return { text: "Tick what to refund." } if quote.empty?

      text = "Back to the buyer: #{helpers.number_to_currency(quote.amount_cents / 100.0)}"
      text += " · from your balance: #{helpers.number_to_currency(quote.org_debit_cents / 100.0)}" if @order.money_path == "cocoscout"
      { text: text }
    end
    helper_method :refund_preview

    # Returning part of a pass prices what they keep at regular, unless the
    # manager chose to refund the full share (reprice=0).
    def reprice?
      params[:reprice] != "0"
    end

    # Refund anyway: a refund outside the policy needs the toggle on, and a
    # reason the order will show. Returns whether this is one.
    def exception_allowed!
      return false if TicketOrderRefund.policy_check(@order).within
      raise TicketOrderRefund::Error, "This refund is outside the refund policy. Turn on Refund anyway to make it." unless params[:outside_policy] == "1"
      raise TicketOrderRefund::Error, "Say why you're refunding outside the policy." if params[:reason].blank?

      true
    end

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
