# frozen_string_literal: true

# Buying tickets, no sign-in. Picking tickets on a show's page holds the seats
# for ten minutes (TicketCheckout) and opens checkout at /t/checkout/<token>.
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
  skip_forgery_protection only: %i[create pay]

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

    profile = TicketingProfile.find_by(slug: params[:org].to_s.downcase)
    listing = profile && profile.organization.ticket_listings.find_by(slug: params[:event])
    raise ActiveRecord::RecordNotFound unless listing && (profile.enabled? || superadmin_viewer?)

    order = TicketCheckout.start!(listing: listing, quantities: requested_quantities,
                                  code: params[:code], client_ip: request.remote_ip, referrer: request.referer)
    redirect_to tickets_checkout_path(token: order.token, **embed_params)
  rescue TicketCheckout::Error => e
    redirect_to tickets_event_path(org: params[:org], event: params[:event], code: params[:code].presence, **embed_params), alert: e.message
  end

  def show
    return redirect_to(tickets_order_path(token: @order.token, **embed_params)) if @order.paid?

    @expired = @order.hold_expired? || @order.status != "pending"
  end

  # The buyer's details are in: record them, then either finish a free order
  # or hand back the PaymentIntent's client secret for Stripe to confirm.
  def pay
    return render(json: { redirect: tickets_order_path(token: @order.token, **embed_params) }) if @order.paid?
    return render(json: { error: "Your hold on these seats ran out. Please start again." }, status: :unprocessable_entity) if @order.hold_expired? || @order.status != "pending"
    return render(json: { error: "Please check your details and try again." }, status: :unprocessable_entity) unless human_pace?

    buyer = params.permit(:buyer_name, :buyer_email, :buyer_phone)
    @order.assign_attributes(buyer_name: buyer[:buyer_name].to_s.squish.presence, buyer_email: buyer[:buyer_email],
                             buyer_phone: buyer[:buyer_phone].to_s.strip.presence)
    if @order.buyer_name.blank? || @order.buyer_email.blank? || !@order.valid?
      return render(json: { error: "Add your name and a valid email so we can send your tickets." }, status: :unprocessable_entity)
    end
    @order.save!

    if @order.total_cents.zero?
      TicketOrderSettlement.settle!(@order)
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
    if @order.stripe_payment_intent_id.present? && !@order.paid?
      intent = Stripe::PaymentIntent.retrieve(@order.stripe_payment_intent_id)
      if intent.status == "succeeded"
        TicketOrderSettlement.settle!(@order, payment_intent_id: intent.id, charge_id: intent.latest_charge)
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

  def set_order
    @order = TicketOrder.includes(ticket_listing: [ :organization, { show: %i[location location_space] } ], tickets: :ticket_tier)
                        .find_by!(token: params[:token])
    @listing = @order.ticket_listing
    @ticketing_profile = TicketingProfile.for(@listing.organization)
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
    if @order.stripe_payment_intent_id.present?
      intent = Stripe::PaymentIntent.retrieve(@order.stripe_payment_intent_id)
      return intent if intent.amount == @order.total_cents && intent.status != "canceled"
    end

    metadata = { type: "ticket_order", ticket_order_id: @order.id, ticket_order_code: @order.code,
                 organization_id: @order.organization_id, ticket_listing_id: @listing.id }
    intent = Stripe::PaymentIntent.create(
      {
        amount: @order.total_cents,
        currency: "usd",
        automatic_payment_methods: { enabled: true },
        description: "#{@listing.display_title} · #{@listing.organization.name}".first(250),
        metadata: metadata,
        # Segregates each org's money flows Stripe-side, like the cash ledger.
        transfer_group: "org_#{@order.organization_id}"
      },
      { idempotency_key: "ticket-order-#{@order.id}-#{@order.total_cents}" }
    )
    @order.update!(stripe_payment_intent_id: intent.id)
    intent
  end

  def superadmin_viewer?
    authenticated? && Current.user&.superadmin?
  end
end
