# frozen_string_literal: true

# Another system the organization uses, connected on Organization settings →
# Integrations (plan §9.3). Square was the first; Google Calendar keeps the
# organization's calendar (Tim, 2026-11-11); the bank's live connection and
# the outside ticket sellers join them in 1.5. Tokens live encrypted in
# credentials; everything the page lets you choose lives in settings.
class Integration < ApplicationRecord
  PROVIDERS = %w[square google_calendar].freeze
  STATUSES = %w[connected error disconnected].freeze

  # What Square brings in, each a switch on its page.
  BRINGS = {
    "sales" => [ "Sales by category", "gross, before tax" ],
    "tips" => [ "Tips", "to the day's tips section, never split on their own" ],
    "tax" => [ "Sales tax collected", "set aside with ticket sales tax; Square does not remit it for you" ],
    "refunds" => [ "Refunds", "against the day they were given" ],
    "fees" => [ "Square's fees", "as card fees" ],
    "deposits" => [ "Deposits to your bank", "so the Bank page can match them" ]
  }.freeze
  # Our money-in categories a register's categories map to.
  REGISTER_CATEGORIES = { "bar" => "Bar", "food" => "Food", "merchandise" => "Merch", "other" => "Other" }.freeze
  SKIP = "skip"

  # How each event's title reads and how long its block is, each a checkbox.
  # A date is one event however it came about: a show made by a contract is
  # that show, blocked for the whole rental when the last of these is on.
  CALENDAR_TITLE_PARTS = {
    "room" => "Room in the title",
    "call_time" => "Call and show times in the title",
    "start_at_call" => "Start the block at call time",
    "rental_block" => "Block the whole rental time when a date is under contract"
  }.freeze
  # The colors Google Calendar offers for an event: its id, name and color.
  CALENDAR_COLORS = {
    "11" => [ "Tomato", "#D50000" ], "4" => [ "Flamingo", "#E67C73" ], "6" => [ "Tangerine", "#F4511E" ],
    "5" => [ "Banana", "#F6BF26" ], "2" => [ "Sage", "#33B679" ], "10" => [ "Basil", "#0B8043" ],
    "7" => [ "Peacock", "#039BE5" ], "9" => [ "Blueberry", "#3F51B5" ], "1" => [ "Lavender", "#7986CB" ],
    "3" => [ "Grape", "#8E24AA" ], "8" => [ "Graphite", "#616161" ]
  }.freeze
  DEFAULT_OTHER_COLOR = "8"
  # Rooms get these, in order, until someone chooses.
  DEFAULT_ROOM_COLORS = %w[7 4 2 6 3 5 10 9 1 11].freeze

  belongs_to :organization
  belongs_to :connected_by, class_name: "User", optional: true
  has_many :register_days, dependent: :destroy
  has_many :register_pulls, dependent: :destroy
  has_many :calendar_sync_events, dependent: :delete_all

  encrypts :credentials

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: STATUSES }

  scope :connected, -> { where(status: %w[connected error]) }
  scope :square, -> { where(provider: "square") }
  scope :google_calendar, -> { where(provider: "google_calendar") }

  def connected? = status != "disconnected"
  def square? = provider == "square"
  def google_calendar? = provider == "google_calendar"

  # Google Calendar: the calendar CocoScout made, whose account it's in,
  # what goes on it, how a title reads, and each room's color.
  def calendar_id = settings["calendar_id"].presence
  def calendar_name = settings["calendar_name"].presence
  def account_email = settings["account_email"].presence
  # Which kinds of event Google Calendar carries: all of them until someone
  # switches one off.
  def calendar_event_type?(type) = settings.fetch("event_types", {}).fetch(type.to_s, true) != false
  def calendar_event_types = EventTypes.all.select { |type| calendar_event_type?(type) }
  def calendar_title_part?(key) = settings.fetch("title", {}).fetch(key, true) != false
  def other_color = CALENDAR_COLORS.key?(settings["other_color"].to_s) ? settings["other_color"].to_s : DEFAULT_OTHER_COLOR

  # A room's color: what someone chose, else the next of the defaults by the
  # room's place among the organization's rooms.
  def room_color(space)
    return other_color unless space

    chosen = settings.fetch("room_colors", {})[space.id.to_s].to_s
    return chosen if CALENDAR_COLORS.key?(chosen)

    index = organization.calendar_rooms.index(space) || 0
    DEFAULT_ROOM_COLORS[index % DEFAULT_ROOM_COLORS.size]
  end

  def tokens
    credentials.present? ? JSON.parse(credentials) : {}
  end

  def tokens=(hash)
    self.credentials = hash.to_json
  end

  def access_token = tokens["access_token"]
  def refresh_token = tokens["refresh_token"]
  def merchant_id = tokens["merchant_id"]
  def token_expires_at = tokens["expires_at"] && Time.zone.parse(tokens["expires_at"])

  def merchant_name = settings["merchant_name"].presence
  def external_locations = Array(settings["locations"])
  def external_categories = Array(settings["categories"])
  def location_map = settings.fetch("location_map", {})
  def category_map = settings.fetch("category_map", {})

  def brings?(key) = settings.fetch("brings", {}).fetch(key, true) != false

  # Which of our locations an external location is, nil for "not ours".
  def our_location_id(external_id)
    value = location_map[external_id]
    return nil if value.blank? || value == SKIP

    value.to_i
  end

  def skipped_location?(external_id) = location_map[external_id] == SKIP

  # A register's category names that speak for themselves, so Bar is Bar
  # before anyone maps it.
  NAMED_CATEGORIES = {
    "bar" => "bar", "drinks" => "bar", "beverages" => "bar", "beer" => "bar", "wine" => "bar", "cocktails" => "bar", "liquor" => "bar",
    "food" => "food", "snacks" => "food", "candy" => "food", "kitchen" => "food",
    "merch" => "merchandise", "merchandise" => "merchandise", "apparel" => "merchandise"
  }.freeze

  # The money-in category an external category maps to: what someone chose,
  # else what its name says, else "other" until someone says.
  def our_category(external_id)
    chosen = category_map[external_id].to_s
    return chosen if REGISTER_CATEGORIES.key?(chosen)

    name = external_categories.find { |c| c["id"] == external_id }&.dig("name").to_s.downcase.strip
    NAMED_CATEGORIES.fetch(name, "other")
  end

  def connect!(tokens:, by:, merchant_name: nil)
    update!(tokens: tokens, status: "connected", connected_by: by, connected_at: Time.current, last_error: nil,
            settings: settings.merge("merchant_name" => merchant_name).compact)
  end

  def disconnect!
    update!(credentials: nil, status: "disconnected", last_error: nil)
  end

  def record_error!(message)
    update!(status: "error", last_error: message.to_s.truncate(500))
  end

  def record_success!
    update!(status: "connected", last_error: nil, last_synced_at: Time.current)
  end
end
