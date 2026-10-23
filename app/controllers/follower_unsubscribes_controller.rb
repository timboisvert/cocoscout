# frozen_string_literal: true

# The link at the bottom of every email to followers (and mail apps'
# one-click unsubscribe, which posts here). Leaving takes them off every list
# that organization keeps; their tickets and receipts still come.
class FollowerUnsubscribesController < ApplicationController
  allow_unauthenticated_access
  # The token is the key; mail apps' one-click unsubscribe posts without a session.
  skip_forgery_protection only: %i[create resubscribe]
  layout "storefront"

  before_action :set_follower

  # Shows the page; its form posts on load (submit-on-load), so a link
  # checker that only fetches the page can't unsubscribe anyone.
  def show; end

  def create
    @follower.unsubscribe! if @follower.subscribed?
    # A mail app's one-click unsubscribe wants a plain answer, not a page.
    return head(:ok) if params["List-Unsubscribe"] == "One-Click"

    redirect_to follower_unsubscribe_path(token: @follower.unsubscribe_token, done: 1), status: :see_other
  end

  def resubscribe
    @follower.resubscribe! unless @follower.subscribed? || EmailSuppression.suppressed?(@follower.email)
    redirect_to follower_unsubscribe_path(token: @follower.unsubscribe_token, back: 1), status: :see_other
  end

  private

  def set_follower
    @follower = Follower.includes(:organization, :mailing_lists).find_by!(unsubscribe_token: params[:token].to_s)
    @organization = @follower.organization
    @storefront_organization = @organization
    @storefront_sold_line = ""
    @storefront_brand = "Sent with CocoScout"
    @storefront_home = nil
  end
end
