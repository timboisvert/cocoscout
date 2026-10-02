# frozen_string_literal: true

# A show that moved after people bought tickets: a new date, time or place.
# Each order remembers what its buyer was told (told_starts_at,
# told_location_id, told_location_space_id: set when they bought). The ones
# told something else are who to tell. Nothing goes out by itself: the show
# page asks, the manager reads and edits the email first (the
# ticket_event_changed template), and TicketShowChangeJob sends it, each with
# that buyer's own "it was". "Mark as told" settles it without an email.
class TicketShowChange
  Draft = Data.define(:orders, :subject, :body)

  CHANGED = "ticket_orders.told_starts_at IS DISTINCT FROM shows.date_and_time OR " \
            "ticket_orders.told_location_id IS DISTINCT FROM shows.location_id OR " \
            "ticket_orders.told_location_space_id IS DISTINCT FROM shows.location_space_id"

  # Every order, anywhere, whose buyer was told something else.
  def self.changed_orders
    TicketOrder.paid_like.where.not(buyer_email: nil).joins(ticket_listing: :show).where(CHANGED)
  end

  def self.orders(listing)
    changed_orders.where(ticket_listing_id: listing.id)
  end

  # Worth asking about: a show still to come, selling, with buyers to tell.
  def self.pending?(listing)
    show = listing.show
    return false if listing.status.in?(%w[draft canceled]) || show.canceled || show.date_and_time <= Time.current

    orders(listing).exists?
  end

  def self.draft(listing)
    template = ContentTemplateService.find_template("ticket_event_changed")
    Draft.new(orders: orders(listing).includes(:tickets).order(:buyer_name, :id).to_a,
              subject: template&.subject.to_s, body: TicketOrderMailer.plain_text(template&.body))
  end

  def self.start!(listing, subject:, body:)
    TicketShowChangeJob.perform_later(listing.id, subject.to_s, body.to_s)
  end

  # These buyers now know what the show says.
  def self.mark_told!(listing, orders = orders(listing))
    show = listing.show
    TicketOrder.where(id: orders.select(:id)).update_all(told_starts_at: show.date_and_time, told_location_id: show.location_id,
                                                         told_location_space_id: show.location_space_id, updated_at: Time.current)
  end

  # The words for one buyer's email: what changed, and when and where it
  # was and is.
  def self.variables(order)
    show = order.ticket_listing.show
    was_location = Location.find_by(id: order.told_location_id)
    was_space = LocationSpace.find_by(id: order.told_location_space_id)
    TicketOrderMailer.ticket_variables(order).merge(
      what_changed: what_changed(order, show),
      now: described(show.date_and_time, show.location, show.location_space),
      was: described(order.told_starts_at || show.date_and_time, was_location, was_space)
    )
  end

  # "date", "time", "date and time", "place", "date, time, and place"…
  def self.what_changed(order, show)
    told = order.told_starts_at
    words = []
    words << "date" if told && told.to_date != show.date_and_time.to_date
    words << "time" if told && told.strftime("%H:%M") != show.date_and_time.strftime("%H:%M")
    words << "place" if order.told_location_id != show.location_id || order.told_location_space_id != show.location_space_id
    words.to_sentence.presence || "time"
  end

  def self.described(time, location, space)
    venue = [ location&.name, space&.name ].compact.uniq.join(", ")
    [ time.strftime("%A, %B %-d at %-l:%M %p"), (" at #{venue}" if venue.present?) ].compact.join(",")
  end

  private_class_method :what_changed, :described
end
