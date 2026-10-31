# frozen_string_literal: true

# A subscriber's own page (/tickets/my-subscription/<token>, from the
# welcome email): their seats, the dates with their tickets, and Renew when
# next season's pass has opened renewal for them.
class TicketSubscriptionsController < ApplicationController
  include TicketingEmbeddable

  allow_unauthenticated_access
  skip_forgery_protection only: :renew

  before_action :set_subscription

  def show
    @orders = @subscription.orders.select { |o| o.status == "paid" }.sort_by { |o| o.ticket_listing.show.date_and_time }
    @renewal = TicketSubscription.find_by(renewed_from_id: @subscription.id)
  end

  def renew
    raise ActiveRecord::RecordNotFound unless @subscription.renewable?

    order = TicketCheckout.start_pass!(pass: @subscription.renewal_pass, quantity: @subscription.quantity, renewing: @subscription,
                                       client_ip: request.remote_ip, referrer: request.referer)
    redirect_to tickets_checkout_path(token: order.token, **embed_params)
  rescue TicketCheckout::Error, Ticketing::Subscriptions::Error => e
    redirect_to tickets_subscription_path(token: @subscription.token, **embed_params), alert: e.message
  end

  private

  def set_subscription
    @subscription = TicketSubscription.includes(:organization, :ticket_pass).find_by!(token: params[:token].to_s)
    raise ActiveRecord::RecordNotFound if @subscription.status == "pending"

    @pass = @subscription.ticket_pass
    @organization = @subscription.organization
    @ticketing_profile = TicketingProfile.for(@organization)
  end
end
