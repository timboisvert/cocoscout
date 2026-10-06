# frozen_string_literal: true

# One show, for sale. Everything a buyer sees about a night comes from here
# and its show: the tiers and their seats, when sales open and close, and the
# fee switch (who pays our 50¢ and card processing).
#
# Nothing goes on sale by itself: a listing starts as a draft, and a manager
# puts it on sale (or schedules on_sale_at) — unless its production has
# ticketing set up (ProductionTicketing), which lists the shows it includes
# with their sales windows. Then a blank field here means "the production's":
# read them through the effective_* methods.
class TicketListing < ApplicationRecord
  STATUSES = %w[draft on_sale paused closed canceled].freeze
  # Online sales close at showtime unless the theater says otherwise; after
  # that it's door sales.
  DEFAULT_RUNTIME = 2.hours
  # "Only N left" shows from this many seats left, unless the production or
  # the date says otherwise.
  LOW_STOCK_DEFAULT = 5

  belongs_to :organization
  belongs_to :show
  belongs_to :production
  belongs_to :contract, optional: true

  has_many :ticket_tiers, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :ticket_listing
  has_many :ticket_orders, dependent: :restrict_with_error
  has_many :tickets
  has_many :ticket_discount_codes, dependent: :destroy
  has_many :ticket_order_items
  has_many :ticket_outside_sales, dependent: :destroy

  # Prices are edited in place on the listing page; an empty new row is skipped.
  accepts_nested_attributes_for :ticket_tiers, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["id"].blank? && attrs["name"].blank? && attrs["price_cents"].to_i.zero? }

  validates :status, inclusion: { in: STATUSES }
  validates :slug, presence: true, uniqueness: { scope: :organization_id },
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :fee_mode, inclusion: { in: TicketingProfile::FEE_MODES }, allow_nil: true
  validates :max_per_order, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validate :show_belongs_to_organization

  before_validation :take_production_and_organization_from_show, on: :create
  before_validation :default_slug, on: :create
  before_validation :default_off_sale_at, on: :create
  # A draft with no sales can go with its show; once anyone has bought, the
  # show has to be cancelled (and refunded) instead.
  before_destroy :keep_listings_with_orders, prepend: true

  scope :on_sale_now, ->(at = Time.current) {
    where(status: "on_sale")
      .where("ticket_listings.on_sale_at IS NULL OR ticket_listings.on_sale_at <= ?", at)
      .where("ticket_listings.off_sale_at IS NULL OR ticket_listings.off_sale_at > ?", at)
  }

  # What buyers see a show called: the listing's own title, else the
  # production ticketing's, else the show's own name, else the production's.
  # (Never the calendar's suggested name — "The Late Show Show" — which is for
  # managers' lists.)
  def display_title
    title.presence || production_ticketing&.title.presence || show.secondary_name.presence || production&.name || show.display_name
  end

  # The production's ticketing setup, when it has one.
  def production_ticketing
    return @production_ticketing if defined?(@production_ticketing)

    @production_ticketing = production&.production_ticketing
  end

  def effective_description
    description.presence || production_ticketing&.description.presence || production&.description.presence
  end

  def effective_door_note
    door_note.presence || production_ticketing&.door_note.presence
  end

  def effective_age_note
    age_note.presence || production_ticketing&.age_note.presence
  end

  def effective_accessibility_note
    accessibility_note.presence || production_ticketing&.accessibility_note.presence
  end

  # Products a buyer can add at this date's checkout: the production's,
  # unless this date switched them off (sell_products). A date without a
  # production setup offers none. At the door (at_door) only when the
  # production sells its products there too: a pre-sold bottle isn't a door
  # item unless the theater says so.
  def product_offers(at_door: false)
    return [] unless sell_products && production_ticketing
    return [] if at_door && !production_ticketing.products_at_door

    production_ticketing.product_offers
  end

  def starts_at
    show.date_and_time
  end

  def ends_at
    starts_at && starts_at + (show.duration_minutes.to_i.positive? ? show.duration_minutes.minutes : DEFAULT_RUNTIME)
  end

  def effective_fee_mode
    fee_mode.presence || production_ticketing&.fee_mode.presence || profile&.default_fee_mode || "buyer"
  end

  def effective_max_per_order
    max_per_order || production_ticketing&.max_per_order || profile&.default_max_per_order || 10
  end

  def effective_low_stock_threshold
    low_stock_threshold || production_ticketing&.low_stock_threshold || LOW_STOCK_DEFAULT
  end

  # "Only 3 left" when a count is at or under the threshold, else nil.
  def low_stock_note(left)
    "Only #{left} left" if left && left.positive? && left <= effective_low_stock_threshold
  end

  def buyer_pays_fees?
    effective_fee_mode == "buyer"
  end

  # Selling online right now: put on sale, inside its window, show not cancelled.
  def selling?(at = Time.current)
    status == "on_sale" && !show.canceled &&
      (on_sale_at.nil? || on_sale_at <= at) &&
      (off_sale_at.nil? || at < off_sale_at)
  end

  def inventory
    Ticketing::Inventory.new(self)
  end

  private

  def profile
    organization&.ticketing_profile
  end

  def take_production_and_organization_from_show
    return unless show

    self.production ||= show.production
    self.organization ||= show.production&.organization
  end

  # "animorphs-oct-10", "animorphs-oct-10-9pm" when the night has two shows.
  def default_slug
    return if slug.present? || show.nil?

    name = (production&.name || show.display_name).to_s.parameterize.first(40).delete_suffix("-").presence || "show"
    date = show.date_and_time
    base = date ? "#{name}-#{date.strftime('%b').downcase}-#{date.day}" : name
    candidate = base
    if organization && TicketListing.where(organization: organization, slug: candidate).exists?
      candidate = "#{base}-#{date.strftime('%-l%P').delete(' ')}" if date
      n = 1
      while TicketListing.where(organization: organization, slug: candidate).exists?
        n += 1
        candidate = "#{base}-#{n}"
      end
    end
    self.slug = candidate
  end

  def default_off_sale_at
    self.off_sale_at ||= production_ticketing ? production_ticketing.off_sale_at_for(show&.date_and_time) : show&.date_and_time
  end

  def show_belongs_to_organization
    return unless show && organization

    errors.add(:show, "belongs to another organization") unless show.production&.organization_id == organization_id
    errors.add(:production, "doesn't match the show") if production_id && show.production_id != production_id
  end

  def keep_listings_with_orders
    return unless ticket_orders.exists?

    errors.add(:base, "This show has ticket orders. Cancel it and refund buyers instead.")
    throw :abort
  end
end
