# frozen_string_literal: true

# Paying for a membership (advanced ticketing §2b): no show, so the
# checkout is the purchase itself, at /tickets/membership-checkout/<token>,
# with the same Payment Element and rules as tickets. Paid, the member
# lands on their card, signed in.
class TicketMembershipPurchasesController < ApplicationController
  include TicketingEmbeddable
  include VerifiedBuyer

  allow_unauthenticated_access
  skip_forgery_protection only: :pay

  before_action :set_purchase
  helper_method :superadmin_viewer?

  def show
    return redirect_to(card_path) if @purchase.paid?

    @expired = @purchase.status != "pending" || @purchase.hold_expired?
  end

  def pay
    return render(json: { redirect: card_path }) if @purchase.paid?
    return render(json: { error: "This checkout ran out. Please start again." }, status: :unprocessable_content) if @purchase.status != "pending" || @purchase.hold_expired?
    return render(json: { error: "Please check your details and try again." }, status: :unprocessable_content) unless human_pace?

    name = params[:buyer_name].to_s.squish
    email = params[:buyer_email].to_s.strip.downcase
    if name.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
      return render(json: { error: "Add your name and a valid email so we can send your membership." }, status: :unprocessable_content)
    end
    @memberships.each { |membership| membership.update!(holder_name: name, holder_email: email) }
    boxes = FollowCheckout.boxes_for(@purchase.organization)
    @purchase.update!(follow_list_ids: FollowCheckout.chosen_ids(params, boxes)) if boxes.any?

    if @purchase.total_cents.zero?
      TicketPurchaseSettlement.settle!(@purchase)
      return render(json: { redirect: card_path })
    end

    render json: { client_secret: payment_intent.client_secret }
  rescue Stripe::StripeError => e
    Rails.logger.error("[TicketMembershipPurchases] purchase #{@purchase.id}: #{e.message}")
    render json: { error: "We couldn't reach our payment processor. Please try again." }, status: :bad_gateway
  end

  def done
    if @purchase.stripe_payment_intent_id.present? && !@purchase.paid?
      intent = Stripe::PaymentIntent.retrieve(@purchase.stripe_payment_intent_id)
      if intent.status == "succeeded"
        TicketPurchaseSettlement.settle!(@purchase, payment_intent_id: intent.id, charge_id: intent.latest_charge)
      elsif intent.status == "requires_payment_method"
        return redirect_to(tickets_membership_purchase_path(token: @purchase.token, **embed_params), alert: "That payment didn't go through. Please try another way to pay.")
      end
    end
    redirect_to card_path
  rescue Stripe::StripeError => e
    Rails.logger.error("[TicketMembershipPurchases] done for purchase #{@purchase.id}: #{e.message}")
    redirect_to card_path
  end

  private

  def set_purchase
    @purchase = TicketPurchase.find_by!(token: params[:token].to_s)
    @memberships = @purchase.ticket_memberships.includes(:level).to_a
    raise ActiveRecord::RecordNotFound if @memberships.empty?

    @membership = @memberships.first
    @level = @membership.level
    @organization = @purchase.organization
    @ticketing_profile = TicketingProfile.for(@organization)
  end

  # Paid, the buyer is who they say: the card's link signs them in too.
  def card_path
    verify_buyer!(@organization, @membership.holder_email) if @purchase.paid? && @membership.holder_email.present?
    tickets_membership_path(token: @membership.token, **embed_params)
  end

  def human_pace?
    return false if params[:website].present?

    @purchase.created_at <= TicketCheckoutsController::MIN_SECONDS_TO_PAY.seconds.ago
  end

  def payment_intent
    if @purchase.stripe_payment_intent_id.present?
      intent = Stripe::PaymentIntent.retrieve(@purchase.stripe_payment_intent_id)
      return intent if intent.amount == @purchase.total_cents && intent.status != "canceled"
    end

    intent = Stripe::PaymentIntent.create(
      { amount: @purchase.total_cents, currency: "usd", automatic_payment_methods: { enabled: true },
        description: "#{@level.name} membership · #{@organization.name}".first(250),
        metadata: { type: "ticket_purchase", ticket_purchase_id: @purchase.id, organization_id: @organization.id, ticket_membership_level_id: @level.id },
        transfer_group: "org_#{@organization.id}" },
      { idempotency_key: "ticket-purchase-#{@purchase.id}-#{@purchase.total_cents}" }
    )
    @purchase.update!(stripe_payment_intent_id: intent.id)
    intent
  end

  def superadmin_viewer?
    authenticated? && Current.user&.superadmin?
  end
end
