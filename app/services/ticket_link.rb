# frozen_string_literal: true

# Where someone gets tickets for a show, one answer for every page that lists
# one (Round 9 §3, 2026-10-06):
#
#   :cocoscout  the date is on sale here: its short link, and a label for how
#               it stands ("Get tickets", "Sold out", "On sale Oct 10"…)
#   :outside    the date's own tickets_url, else its production's ("Get tickets ↗")
#   :none       nothing to link
#
# `for_all` answers many shows with a handful of queries and never writes a
# short link during a page view (a selling production already has one).
class TicketLink
  Link = Struct.new(:kind, :url, :label, :state, :site, keyword_init: true) do
    def cocoscout? = kind == :cocoscout
    def outside? = kind == :outside
    def none? = kind == :none
  end
  NONE = Link.new(kind: :none).freeze

  # Sites a pasted link is recognized as: the name becomes a ticket source for
  # the organization's financials. Anything else is named after its host.
  KNOWN_SITES = {
    "tickettailor.com" => "Ticket Tailor", "eventbrite.com" => "Eventbrite", "eventbrite.co.uk" => "Eventbrite", "eventbrite.ca" => "Eventbrite",
    "hottix.org" => "HotTix", "brownpapertickets.com" => "Brown Paper Tickets", "universe.com" => "Universe", "showclix.com" => "ShowClix",
    "dice.fm" => "DICE", "tixr.com" => "Tixr", "ticketleap.com" => "TicketLeap", "ticketleap.events" => "TicketLeap", "ticketweb.com" => "TicketWeb",
    "humanitix.com" => "Humanitix", "ticketmaster.com" => "Ticketmaster", "axs.com" => "AXS", "seetickets.com" => "See Tickets", "seetickets.us" => "See Tickets",
    "goldstar.com" => "Goldstar", "todaytix.com" => "TodayTix", "ovationtix.com" => "OvationTix", "squareup.com" => "Square", "square.site" => "Square",
    "crowdwork.com" => "CrowdWork", "thundertix.com" => "ThunderTix", "ludus.com" => "Ludus", "purplepass.com" => "Purplepass", "simpletix.com" => "SimpleTix",
    "etix.com" => "Etix", "stubs.net" => "Stubs", "vendini.com" => "Vendini", "withfriends.co" => "Withfriends", "ticketsource.co.uk" => "TicketSource",
    "ticketspice.com" => "TicketSpice", "zeffy.com" => "Zeffy", "givebutter.com" => "Givebutter", "shopify.com" => "Shopify", "wix.com" => "Wix",
    "squarespace.com" => "Squarespace", "facebook.com" => "Facebook", "instagram.com" => "Instagram", "linktr.ee" => "Linktree"
  }.freeze

  # A pasted link, read: { url: (with a scheme), host:, name:, known: }.
  # nil when it isn't a link at all.
  def self.recognize(text)
    raw = text.to_s.strip
    return nil if raw.blank?

    raw = "https://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
    uri = URI.parse(raw)
    return nil unless uri.host.present? && uri.host.include?(".")

    host = uri.host.downcase.delete_prefix("www.")
    key = KNOWN_SITES.keys.find { |site| host == site || host.end_with?(".#{site}") }
    name = key ? KNOWN_SITES[key] : host.split(".")[-2].to_s.tr("-_", "  ").split.map(&:capitalize).join(" ")
    { url: uri.to_s, host: host, name: name, known: key.present? }
  rescue URI::InvalidURIError
    nil
  end

  # One show's link. `public:` hides a CocoScout link while the box office is
  # closed or the date is a draft (a manager still sees it on their own pages).
  def self.for(show, public: false, listing: :load, production: nil, profile: nil, code: nil)
    production ||= show.production
    listing = show.ticket_listing if listing == :load
    if listing && listing.status != "draft" && listing.status != "canceled" && !show.canceled
      profile ||= TicketingProfile.for(production.organization)
      return NONE if public && !profile.enabled?

      code ||= ShortLink.canonical_for!(production).code
      return cocoscout(listing, code)
    end

    # A date answering for itself: its own link, or no tickets. Otherwise the production's.
    return NONE if show.tickets_mode == "none"

    url = show.tickets_mode == "elsewhere" ? show.tickets_url.presence : production.tickets_url.presence
    return NONE if url.blank? || (show.tickets_mode.nil? && production.tickets_mode == "none")

    site = recognize(url)
    Link.new(kind: :outside, url: url, label: "Get tickets", state: :outside, site: site && site[:name])
  end

  # Many shows at once: { show_id => Link }. Shows must carry their production
  # (pass them loaded with `includes(:production, :ticket_listing)`).
  def self.for_all(shows, public: false)
    shows = Array(shows)
    return {} if shows.empty?

    listings = TicketListing.where(show_id: shows.map(&:id)).where.not(status: %w[draft canceled]).index_by(&:show_id)
    productions = shows.map(&:production).compact.uniq
    selling = productions.select { |p| listings.values.any? { |l| l.production_id == p.id } }
    codes = ShortLink.where(target_type: "Production", target_id: selling.map(&:id), kind: "canonical").pluck(:target_id, :code).to_h
    selling.each { |p| codes[p.id] ||= ShortLink.canonical_for!(p).code }
    profiles = TicketingProfile.where(organization_id: productions.map(&:organization_id).uniq).index_by(&:organization_id)
    shows.to_h do |show|
      production = show.production
      profile = production && (profiles[production.organization_id] || TicketingProfile.new(enabled: false))
      [ show.id, self.for(show, public: public, listing: listings[show.id], production: production, profile: profile, code: production && codes[production.id]) ]
    end
  end

  def self.cocoscout(listing, code)
    at = Time.current
    inventory = listing.inventory
    state, label =
      if inventory.sold_out? then [ :sold_out, "Sold out" ]
      elsif listing.status == "paused" then [ :paused, "Not on sale right now" ]
      elsif listing.status == "closed" || listing.off_sale_at&.<=(at) then [ :closed, "Tickets at the door" ]
      elsif listing.on_sale_at&.>(at) then [ :upcoming, "On sale #{listing.on_sale_at.strftime('%b %-d')}" ]
      else [ :on_sale, "Get tickets" ]
      end
    url = Rails.application.routes.url_helpers.short_link_url(code: code, date: ShortLink.date_suffix(listing.show), **url_options)
    Link.new(kind: :cocoscout, url: url, label: label, state: state, site: "CocoScout")
  end
  private_class_method :cocoscout

  def self.url_options
    Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
  end
  private_class_method :url_options
end
