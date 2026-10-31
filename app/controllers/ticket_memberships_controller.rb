# frozen_string_literal: true

# A member's own card (/tickets/my-membership/<token>, from the welcome
# email): the level, its perks, when it runs, the tickets bought with it,
# and Renew when the window is open. Opening it by its token signs the
# member in (the link came to their email).
class TicketMembershipsController < ApplicationController
  include TicketingEmbeddable
  include VerifiedBuyer

  allow_unauthenticated_access
  skip_forgery_protection only: :renew

  before_action :set_membership

  def show
    verify_buyer!(@organization, @membership.holder_email) if @membership.holder_email.present? && verified_buyer_email(@organization) != @membership.holder_email
    @orders = @membership.ticket_orders.where(status: "paid").includes(ticket_listing: :show).order(created_at: :desc).limit(20).to_a
    @renewal = @membership.renewed_from_id ? nil : TicketMembership.find_by(renewed_from_id: @membership.id)
  end

  def renew
    raise ActiveRecord::RecordNotFound unless @membership.renewable?

    purchase = Ticketing::Memberships.start!(level: @membership.level, renewed_from: @membership)
    redirect_to tickets_membership_purchase_path(token: purchase.token, **embed_params)
  rescue Ticketing::Memberships::Error => e
    redirect_to tickets_membership_path(token: @membership.token, **embed_params), alert: e.message
  end

  private

  def set_membership
    @membership = TicketMembership.includes(:organization, :level).find_by!(token: params[:token].to_s)
    raise ActiveRecord::RecordNotFound if @membership.status == "pending"

    @level = @membership.level
    @organization = @membership.organization
    @ticketing_profile = TicketingProfile.for(@organization)
  end
end
