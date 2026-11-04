# frozen_string_literal: true

# Another system the organization uses, connected on Organization settings →
# Integrations (plan §9.3). Square is the first; the bank's live connection
# and the outside ticket sellers join it in 1.5. Tokens live encrypted in
# credentials; everything the page lets you choose lives in settings.
class Integration < ApplicationRecord
  PROVIDERS = %w[square].freeze
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

  belongs_to :organization
  belongs_to :connected_by, class_name: "User", optional: true
  has_many :register_days, dependent: :destroy
  has_many :register_pulls, dependent: :destroy

  encrypts :credentials

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :organization_id }
  validates :status, inclusion: { in: STATUSES }

  scope :connected, -> { where(status: %w[connected error]) }
  scope :square, -> { where(provider: "square") }

  def connected? = status != "disconnected"
  def square? = provider == "square"

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
