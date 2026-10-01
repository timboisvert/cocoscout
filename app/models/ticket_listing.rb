# frozen_string_literal: true

# One show, for sale. Everything a buyer sees about a night comes from here
# and its show: the tiers and their seats, when sales open and close, and the
# fee switch (who pays our 50¢ and card processing).
#
# Nothing goes on sale by itself: a listing starts as a draft, and a manager
# puts it on sale (or schedules on_sale_at).
class TicketListing < ApplicationRecord
  STATUSES = %w[draft on_sale paused closed canceled].freeze
  # Online sales close at showtime unless the theater says otherwise; after
  # that it's door sales.
  DEFAULT_RUNTIME = 2.hours

  belongs_to :organization
  belongs_to :show
  belongs_to :production
  belongs_to :contract, optional: true

  has_many :ticket_tiers, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :ticket_listing
  has_many :ticket_orders, dependent: :restrict_with_error
  has_many :tickets
  has_many :ticket_discount_codes, dependent: :destroy

  has_one_attached :image

  validates :status, inclusion: { in: STATUSES }
  validates :slug, presence: true, uniqueness: { scope: :organization_id },
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :fee_mode, inclusion: { in: TicketingProfile::FEE_MODES }, allow_nil: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
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

  def display_title
    title.presence || show.display_name
  end

  def starts_at
    show.date_and_time
  end

  def ends_at
    starts_at && starts_at + (show.duration_minutes.to_i.positive? ? show.duration_minutes.minutes : DEFAULT_RUNTIME)
  end

  def effective_fee_mode
    fee_mode.presence || profile&.default_fee_mode || "buyer"
  end

  def effective_max_per_order
    max_per_order || profile&.default_max_per_order || 10
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
    self.off_sale_at ||= show&.date_and_time
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
