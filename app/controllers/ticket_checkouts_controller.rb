# frozen_string_literal: true

# Buying tickets, no sign-in. Picking tickets on a show's page holds the seats
# for ten minutes (TicketCheckout) and opens checkout at /tickets/checkout/<token>.
#
# Payment is Stripe's Payment Element on our own page — cards, Apple Pay,
# Google Pay, Link — so it works inside an embed too. The PaymentIntent is
# only created once the buyer's details are in (pay), on CocoScout's own
# account like course and contract money, and the order settles when Stripe
# says the money arrived (webhook, or the buyer's return here — whichever is
# first). Free orders skip Stripe.
class TicketCheckoutsController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access
  # Buying never rides on a signed-in session: the order's secret token is the
  # key. And inside a theater's own website (the embed) browsers don't send
  # our session cookie, so a forgery token could never verify there.
  skip_forgery_protection only: %i[create pay items]

  # Nobody loads checkout, types their details and pays this fast; a script
  # posting straight through does.
  MIN_SECONDS_TO_PAY = 3

  before_action :set_order, except: :create

  def create
    # A filled-in honeypot (tickets/_bot_trap): no seats held, nothing to learn.
    if params[:website].present?
      Rails.logger.warn("[TicketCheckouts] honeypot tripped on start ip=#{request.remote_ip}")
      return redirect_to(tickets_event_path(org: params[:org], event: params[:event], **embed_params))
    end

    profile, = TicketingProfile.at_address(params[:org])
    listing = profile && profile.organization.ticket_listings.find_by(slug: params[:event])
    raise ActiveRecord::RecordNotFound unless listing && (profile.enabled? || preview_viewer?(profile.organization))

    order = TicketCheckout.start!(listing: listing, quantities: requested_quantities, code: params[:code],
                                  client_ip: request.remote_ip, referrer: request.referer, replacing: params[:hold],
                                  via: cookies[ShortLinksController::COOKIE])
    redirect_to tickets_checkout_path(token: order.token, **embed_params)
  rescue TicketCheckout::Error => e
    redirect_to tickets_event_path(org: params[:org], event: params[:event], code: params[:code].presence, **embed_params), alert: e.message
  end

  def show
    return redirect_to(tickets_order_path(token: @order.token, **embed_params)) if @order.paid?

    @expired = @order.hold_expired? || @order.status != "pending"
    @deals = @expired ? [] : TicketCheckout.deals_for(@order)
    TicketOffer.where(id: @deals.map { |offer, _, _| offer.id }).update_all("shown_count = shown_count + 1") if @deals.any?
  end

  # Is this hold still the buyer's? The show's page asks when they come back
  # from checkout, so it can put their tickets back in the pickers. Only the
  # secret token gets an answer, and only about its own order.
  def hold
    holding = @order.ticket_listing.ticket_orders.holding.exists?(id: @order.id)
    render json: {
      holding: holding,
      listing_id: @listing.id,
      quantities: holding ? TicketCheckout.held_quantities(@order).transform_keys(&:to_s) : {},
      code: holding ? @order.ticket_discount_code&.code : nil,
      expires_at: holding ? @order.expires_at.iso8601 : nil
    }
  end

  # The products the buyer added (or took off) on the checkout page. The
  # order is repriced and the page gets its new summary and total.
  def items
    return render(json: { error: "This order can't be changed anymore." }, status: :unprocessable_content) unless @order.pending? && !@order.hold_expired?

    TicketCheckout.set_items!(@order, requested_products)
    TicketCheckout.set_deals!(@order, requested_deals) if params.key?(:deals)
    @order.reload
    render json: {
      total_cents: payable.reload.total_cents,
      summary_html: render_to_string(partial: "ticket_checkouts/summary", formats: [ :html ], locals: { order: @order }),
      items: @order.ticket_order_items.to_h { |item| [ item.ticket_product_id.to_s, item.quantity ] }
    }
  rescue TicketCheckout::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # The buyer's details are in: record them, then either finish a free order
  # or hand back the PaymentIntent's client secret for Stripe to confirm.
  def pay
    return render(json: { redirect: tickets_order_path(token: @order.token, **embed_params) }) if @order.paid?
    return render(json: { error: "Your hold on these seats ran out. Please start again." }, status: :unprocessable_content) if @order.hold_expired? || @order.status != "pending"
    return render(json: { error: "Please check your details and try again." }, status: :unprocessable_content) unless human_pace?

    # At the door (the buyer paying on their own phone) the details are
    # optional, and a name the door typed in stays unless they give one.
    at_door = @order.channel == "door_card"
    buyer = params.permit(:buyer_name, :buyer_email, :buyer_phone)
    @order.assign_attributes(buyer_name: buyer[:buyer_name].to_s.squish.presence || (@order.buyer_name if at_door),
                             buyer_email: buyer[:buyer_email].presence, buyer_phone: buyer[:buyer_phone].to_s.strip.presence)
    if !@order.valid? || (!at_door && (@order.buyer_name.blank? || @order.buyer_email.blank?))
      message = at_door ? "Check your email address, or leave it blank." : "Add your name and a valid email so we can send your tickets."
      return render(json: { error: message }, status: :unprocessable_content)
    end
    @order.save!
    # Every show's order in the checkout belongs to the same buyer.
    if @purchase
      @purchase.ticket_orders.where.not(id: @order.id).update_all(buyer_name: @order.buyer_name, buyer_email: @order.buyer_email,
                                                                  buyer_phone: @order.buyer_phone, updated_at: Time.current)
    end

    if payable.total_cents.zero?
      settle!
      return render(json: { redirect: tickets_order_path(token: @order.token, **embed_params) })
    end

    render json: { client_secret: payment_intent.client_secret }
  rescue Stripe::StripeError => e
    Rails.logger.error("[TicketCheckouts] order #{@order.id}: #{e.message}")
    render json: { error: "We couldn't reach our payment processor. Please try again." }, status: :bad_gateway
  end

  # Stripe sends the buyer back here. The webhook is the source of truth, but
  # settle now too so the page tells the truth straight away.
  def done
    if intent_id.present? && !@order.paid?
      intent = Stripe::PaymentIntent.retrieve(intent_id)
      if intent.status == "succeeded"
        settle!(payment_intent_id: intent.id, charge_id: intent.latest_charge)
      elsif intent.status == "requires_payment_method"
        return redirect_to(tickets_checkout_path(token: @order.token, **embed_params), alert: "That payment didn't go through. Please try another way to pay.")
      end
    end
    redirect_to tickets_order_path(token: @order.token, **embed_params)
  rescue Stripe::StripeError => e
    Rails.logger.error("[TicketCheckouts] done for order #{@order.id}: #{e.message}")
    redirect_to tickets_order_path(token: @order.token, **embed_params)
  end

  private

  # { tier_id => count } from the ticket page's pickers — plain strings only.
  def requested_quantities
    raw = params[:quantities]
    return {} unless raw.respond_to?(:each_pair)

    raw.each_pair.to_h { |tier_id, count| [ tier_id.to_s, count.to_s ] }
  end

  # { product_id => count } from the checkout page's steppers.
  def requested_products
    raw = params[:products]
    return {} unless raw.respond_to?(:each_pair)

    raw.each_pair.to_h { |id, count| [ id.to_s, count.to_s ] }
  end

  # { offer_id => count } from the checkout page's deal steppers.
  def requested_deals
    raw = params[:deals]
    return {} unless raw.respond_to?(:each_pair)

    raw.each_pair.to_h { |id, count| [ id.to_s, count.to_s ] }
  end

  def set_order
    @order = TicketOrder.includes(ticket_listing: [ :organization, { show: %i[location location_space] } ], tickets: :ticket_tier)
                        .find_by!(token: params[:token])
    @listing = @order.ticket_listing
    @purchase = @order.ticket_purchase
    @ticketing_profile = TicketingProfile.for(@listing.organization)
  end

  # What the buyer pays for: the whole checkout, or (an order from before
  # checkouts held several shows) the order alone.
  def payable
    @purchase || @order
  end

  # The checkout's PaymentIntent (its first order carries the id too).
  def intent_id
    payable.stripe_payment_intent_id.presence || @order.stripe_payment_intent_id
  end

  def settle!(payment_intent_id: nil, charge_id: nil)
    if @purchase
      TicketPurchaseSettlement.settle!(@purchase, payment_intent_id: payment_intent_id, charge_id: charge_id)
    else
      TicketOrderSettlement.settle!(@order, payment_intent_id: payment_intent_id, charge_id: charge_id)
    end
  end

  # One PaymentIntent per order, reused if the buyer tries again, re-priced if
  # the amount somehow moved.
  # The honeypot is empty and the buyer spent a human amount of time here.
  def human_pace?
    if params[:website].present?
      Rails.logger.warn("[TicketCheckouts] honeypot tripped on pay order=#{@order.id} ip=#{request.remote_ip}")
      return false
    end
    return true if @order.created_at <= MIN_SECONDS_TO_PAY.seconds.ago

    Rails.logger.warn("[TicketCheckouts] paid too fast order=#{@order.id} ip=#{request.remote_ip}")
    false
  end

  def payment_intent
    if intent_id.present?
      intent = Stripe::PaymentIntent.retrieve(intent_id)
      return intent if intent.amount == payable.total_cents && intent.status != "canceled"
    end

    metadata = { type: "ticket_order", ticket_order_id: @order.id, ticket_order_code: @order.code,
                 organization_id: @order.organization_id, ticket_listing_id: @listing.id }
    metadata = metadata.merge(type: "ticket_purchase", ticket_purchase_id: @purchase.id) if @purchase
    intent = Stripe::PaymentIntent.create(
      {
        amount: payable.total_cents,
        currency: "usd",
        automatic_payment_methods: { enabled: true },
        description: "#{@listing.display_title} · #{@listing.organization.name}".first(250),
        metadata: metadata,
        # Segregates each org's money flows Stripe-side, like the cash ledger.
        transfer_group: "org_#{@order.organization_id}"
      },
      { idempotency_key: @purchase ? "ticket-purchase-#{@purchase.id}-#{@purchase.total_cents}" : "ticket-order-#{@order.id}-#{@order.total_cents}" }
    )
    # The first order carries the payment's id too, so everything that finds
    # an order by its payment still does.
    (@purchase&.primary_order || @order).update!(stripe_payment_intent_id: intent.id)
    @purchase&.update!(stripe_payment_intent_id: intent.id)
    intent
  end

  def superadmin_viewer?
    authenticated? && Current.user&.superadmin?
  end
  helper_method :superadmin_viewer?

  # A closed box office can be tried by the organization's own managers.
  def preview_viewer?(organization)
    authenticated? && (Current.user&.superadmin? || organization&.manageable_by?(Current.user))
  end
end
