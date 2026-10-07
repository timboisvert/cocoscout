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
  before_action -> { require_level(:box_office) }, only: %i[sell card card_status card_cancel use_pass]
  before_action :set_card_order, only: %i[card card_status card_cancel]

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
    @tiers = @listing.ticket_tiers.active.select(&:available?)
    @offers = @listing.product_offers(at_door: true)
    @orders = parties
  end

  # Everyone with a ticket, one row per party, for the list to refresh.
  def list
    render partial: "door/list", locals: { orders: parties, listing: @listing }
  end

  # The products still to deliver, for the door page to refresh.
  def deliveries
    render partial: "door/deliveries", locals: { listing: @listing }
  end

  # A bottle delivered to the table: the whole line.
  def fulfill
    item = @listing.ticket_order_items.sold.find(params[:item_id])
    item.update!(fulfilled_quantity: item.quantity, fulfilled_at: Time.current, fulfilled_by: Current.user)
    render json: { ok: true, message: "#{item.label} delivered", counts: door.counts }
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
                   holder: order.buyer_name.presence, party: party_line(order), items: items_json(order),
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
      scope = @listing.ticket_orders.paid_like.includes(:ticket_order_items, tickets: %i[ticket_tier ticket_pass]).order(:buyer_name)
      scope.where(code: q.upcase)
           .or(scope.where("ticket_orders.buyer_name ILIKE ?", "%#{TicketOrder.sanitize_sql_like(q)}%"))
           .or(scope.where("ticket_orders.buyer_email ILIKE ?", "%#{TicketOrder.sanitize_sql_like(q)}%"))
           .limit(20).to_a
    end
    @holdings = q.length < 2 ? [] : pass_holders(q)
    render partial: "door/search_results", locals: { orders: @orders, query: q, listing: @listing, holdings: @holdings }
  end

  # Someone with a punch card or season pass at the door: a credit becomes
  # their tickets, checked in at once (TicketPassCredits).
  def use_pass
    holding = TicketPassHolding.active.where(organization_id: @listing.organization_id).find(params[:holding_id])
    order = TicketPassCredits.use!(holding, listing: @listing, people: params[:people] || 1, by: Current.user, at_door: true)
    redirect_to door_path(@listing), notice: "#{holding.holder_name.presence || 'Pass holder'}: #{helpers.pluralize(order.tickets.size, 'ticket')} from their pass, checked in."
  rescue TicketPassCredits::Error => e
    redirect_to door_path(@listing), alert: e.message
  end

  # Live credit passes covering this show whose holder matches a search.
  def pass_holders(query)
    like = "%#{TicketPassHolding.sanitize_sql_like(query)}%"
    TicketPassHolding.active.joins(ticket_pass: :coverages).includes(:ticket_pass)
                     .where(organization_id: @listing.organization_id, ticket_pass_coverages: { production_id: @listing.production_id })
                     .where("ticket_pass_holdings.holder_name ILIKE :q OR ticket_pass_holdings.holder_email ILIKE :q", q: like)
                     .where(ends_on: @listing.show.date_and_time.to_date..).limit(10).to_a.select(&:usable?)
  end

  def stats
    render json: door.counts
  end

  # Selling to someone at the door: cash and comps are recorded and checked
  # in on the spot; card or phone pay holds the seats and shows a QR code the
  # buyer scans to pay on their own phone (card).
  def sell
    quantities = params[:quantities].respond_to?(:each_pair) ? params[:quantities].each_pair.to_h { |k, v| [ k.to_s, v.to_s ] } : {}
    products = params[:products].respond_to?(:each_pair) ? params[:products].each_pair.to_h { |k, v| [ k.to_s, v.to_s ] } : {}
    kind = params[:kind].presence_in(%w[card cash comp]) || "cash"
    if kind == "card"
      order = TicketCheckout.start!(listing: @listing, quantities: quantities, channel: "door_card", at_door: true,
                                    client_ip: request.remote_ip)
      order.update!(buyer_name: params[:buyer_name].to_s.squish.presence, issued_by: Current.user)
      TicketCheckout.set_items!(order, products) if products.values.any? { |v| v.to_i.positive? }
      return redirect_to(door_card_path(@listing, token: order.token))
    end

    order = door.sell(quantities, kind: kind, buyer_name: params[:buyer_name], products: products)
    count = order.tickets.size
    extras = order.ticket_order_items.sum(:quantity)
    sold = extras.positive? ? "#{count} and #{helpers.pluralize(extras, 'product')}" : count.to_s
    redirect_to door_path(@listing), notice: kind == "cash" ? "Sold #{sold} at the door — collect #{helpers.number_to_currency(order.total_cents / 100.0)} cash." : "Comped #{count} and checked them in."
  rescue TicketCheckout::Error => e
    redirect_to door_path(@listing), alert: e.message
  end

  # The door phone while the buyer pays on theirs: a QR code that opens
  # checkout for this order, and the total.
  def card
    return redirect_to(door_path(@listing), notice: "Paid. #{card_paid_message}") if @order.paid?

    @checkout_url = tickets_checkout_url(token: @order.token)
  end

  def card_status
    status = if @order.paid? then "paid"
    elsif @order.status != "pending" || @order.hold_expired? then "expired"
    else "pending"
    end
    render json: { status: status, message: (card_paid_message if status == "paid"), counts: door.counts }
  end

  # They changed their mind: the seats go back.
  def card_cancel
    @order.update!(status: "expired", expires_at: Time.current) if @order.pending?
    redirect_to door_path(@listing), notice: "Canceled. Nothing was charged."
  end

  private

  # Alphabetical by name; nameless (a door sale) at the end by order code.
  def parties
    @listing.ticket_orders.paid_like.includes(:ticket_order_items, tickets: %i[ticket_tier ticket_pass])
            .order(Arel.sql("LOWER(COALESCE(NULLIF(ticket_orders.buyer_name, ''), 'zzzz')), ticket_orders.id")).to_a
  end

  def set_card_order
    @order = @listing.ticket_orders.where(channel: "door_card").find_by!(token: params[:token].to_s)
  end

  def card_paid_message
    count = @order.tickets.where(status: Ticket::SOLD_STATUSES).count
    "#{helpers.pluralize(count, 'ticket')} paid by card, checked in."
  end

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

  # What the banner shows after a scan: who, the result, how much of their
  # party is in, and anything they pre-bought (a bottle) with a Delivered tap.
  def result_json(result)
    ticket = result.ticket
    order = ticket&.ticket_order
    {
      kind: result.kind,
      message: result.message,
      holder: ticket && (ticket.holder_name.presence || order.buyer_name),
      order_code: order&.code,
      ticket_id: ticket&.id,
      party: order && order.ticket_listing_id == @listing.id ? party_line(order) : nil,
      items: order && order.ticket_listing_id == @listing.id ? items_json(order) : [],
      counts: door.counts
    }
  end

  # "2 of 3 in" for a party of several; nothing for a single ticket.
  def party_line(order)
    held = order.tickets.select { |t| Ticket::SOLD_STATUSES.include?(t.status) }
    return nil if held.size < 2

    "#{held.count(&:checked_in?)} of #{held.size} in"
  end

  def items_json(order)
    order.ticket_order_items.select(&:sold?).map do |item|
      { id: item.id, label: item.label, fulfilled: item.fulfilled?, fulfill_url: door_fulfill_path(@listing, item_id: item.id) }
    end
  end
end
