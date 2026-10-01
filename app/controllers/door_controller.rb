# frozen_string_literal: true

# The door on show night, on a phone or tablet. /door lists the shows someone
# can work; /door/<listing> scans tickets, finds people by name or order code,
# checks in whole parties, and (box office and managers) sells and comps at
# the door. Door people aren't always members of the theater — staff, or any
# CocoScout user granted access in Ticketing settings — so this lives outside
# /manage. Signed-in only; access is checked against the show's organization.
class DoorController < ApplicationController
  layout "door"

  before_action :set_listing, except: :index
  before_action -> { require_level(:box_office) }, only: :sell

  def index
    organizations = TicketingDoorAccess.organizations_for(Current.user)
    @listings = TicketListing.where(organization: organizations).where.not(status: %w[draft canceled])
                             .joins(:show).where(shows: { canceled: false })
                             .where("shows.date_and_time >= ?", Time.current.beginning_of_day)
                             .includes(:organization, :production, show: :location)
                             .order("shows.date_and_time").limit(40).to_a
  end

  def show
    @counts = door.counts
    @tiers = @listing.ticket_tiers.active.to_a
  end

  def check_in
    render json: result_json(door.check_in(params[:code]))
  end

  def check_in_order
    order = @listing.ticket_orders.paid_like.find(params[:order_id])
    results = door.check_in_order(order)
    admitted = results.count { |r| r.kind == :admitted }
    render json: { kind: admitted.positive? ? "admitted" : "already",
                   message: admitted.positive? ? "Admitted #{admitted} — #{order.buyer_name.presence || order.code}" : "Everyone on this order is already in",
                   counts: door.counts }
  end

  def undo
    ticket = @listing.tickets.find(params[:ticket_id])
    ok = door.undo(ticket, manager: @level == :manager)
    render json: { ok: ok, message: ok ? "Check-in undone" : "That can't be undone from here", counts: door.counts }
  end

  def search
    q = params[:q].to_s.strip
    @orders = if q.length < 2
      []
    else
      scope = @listing.ticket_orders.paid_like.includes(:tickets).order(:buyer_name)
      scope.where(code: q.upcase)
           .or(scope.where("ticket_orders.buyer_name ILIKE ?", "%#{TicketOrder.sanitize_sql_like(q)}%"))
           .or(scope.where("ticket_orders.buyer_email ILIKE ?", "%#{TicketOrder.sanitize_sql_like(q)}%"))
           .limit(20).to_a
    end
    render partial: "door/search_results", locals: { orders: @orders, query: q }
  end

  def stats
    render json: door.counts
  end

  def sell
    quantities = params[:quantities].respond_to?(:each_pair) ? params[:quantities].each_pair.to_h { |k, v| [ k.to_s, v.to_s ] } : {}
    kind = params[:kind].presence_in(%w[cash comp]) || "cash"
    order = door.sell(quantities, kind: kind, buyer_name: params[:buyer_name])
    count = order.tickets.size
    redirect_to door_path(@listing), notice: kind == "cash" ? "Sold #{count} at the door — collect #{helpers.number_to_currency(order.total_cents / 100.0)} cash." : "Comped #{count} and checked them in."
  rescue TicketCheckout::Error => e
    redirect_to door_path(@listing), alert: e.message
  end

  private

  # Found by id, then judged against its own organization: someone without
  # door access there gets a plain not-found.
  def set_listing
    @listing = TicketListing.includes(:organization, :production, show: %i[location location_space]).find(params[:listing_id])
    @level = TicketingDoorAccess.level_for(Current.user, @listing.organization)
    profile = @listing.organization.ticketing_profile
    raise ActiveRecord::RecordNotFound unless @level && (profile&.enabled? || Current.user.superadmin?)
  end

  def require_level(needed)
    return if TicketingDoorAccess.at_least?(@level, needed)

    respond_to do |format|
      format.json { render json: { error: "Only box office can do that" }, status: :forbidden }
      format.html { redirect_to door_path(@listing), alert: "Selling at the door needs box office access." }
    end
  end

  def door
    @door ||= TicketDoor.new(@listing, Current.user)
  end

  def result_json(result)
    ticket = result.ticket
    {
      kind: result.kind,
      message: result.message,
      holder: ticket && (ticket.holder_name.presence || ticket.ticket_order.buyer_name),
      order_code: ticket&.ticket_order&.code,
      ticket_id: ticket&.id,
      counts: door.counts
    }
  end
end
