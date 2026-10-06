# frozen_string_literal: true

# Tickets to several shows sold as one thing: "Twilight Double Feature, both
# nights for $30", or Boylesque and Laugh Along Live on the same night. A
# dated pass names its shows and the ticket type at each; buying one takes a
# seat at every show (TicketCheckout.start_pass!), in one checkout with one
# payment, one order per show.
#
# Each show's ticket carries that show's share of the pass price, which is
# what its financials, any contract split and its tax see. The split is the
# manager's choice: in proportion to each show's regular price (the default),
# evenly, or shares they type that add up to the price.
class TicketPass < ApplicationRecord
  include HasWideImage

  KINDS = %w[dated].freeze
  SPLITS = %w[regular_price even custom].freeze
  STATUSES = %w[draft on_sale closed].freeze

  belongs_to :organization
  has_many :pass_shows, -> { order(:position, :id) }, class_name: "TicketPassShow", dependent: :destroy, inverse_of: :ticket_pass
  has_many :tickets, dependent: :restrict_with_error
  accepts_nested_attributes_for :pass_shows, allow_destroy: true, reject_if: ->(attrs) { attrs[:ticket_tier_id].blank? }

  normalizes :slug, with: ->(slug) { slug.to_s.parameterize.presence }

  validates :name, presence: true, length: { maximum: 80 }
  validates :slug, presence: true, uniqueness: { scope: :organization_id }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :kind, inclusion: { in: KINDS }
  validates :split, inclusion: { in: SPLITS }
  validates :status, inclusion: { in: STATUSES }
  validates :max_sold, :max_per_order, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :at_least_two_shows, if: -> { status == "on_sale" }
  validate :custom_shares_add_up, if: -> { split == "custom" }

  before_validation { self.slug = name if slug.blank? && name.present? }

  scope :on_sale, -> { where(status: "on_sale") }

  # The shows in date order, with what's needed to sell them.
  def rows
    pass_shows.includes(:ticket_tier, ticket_listing: [ :organization, { show: :location } ]).to_a
              .sort_by { |row| [ row.ticket_listing.starts_at || Time.zone.at(0), row.position ] }
  end

  # Each show's share of one pass, in the order of `rows`, adding up to the
  # price.
  def shares(for_rows = rows)
    case split
    when "even" then TicketPricing.share(price_cents, Array.new(for_rows.size, 1))
    when "custom" then for_rows.map { |row| row.share_cents.to_i }
    else TicketPricing.share(price_cents, for_rows.map { |row| row.ticket_tier.price_cents })
    end
  end

  # The regular prices added up: what the shows cost bought separately,
  # before fees and tax.
  def separately_cents(for_rows = rows)
    for_rows.sum { |row| row.ticket_tier.price_cents }
  end

  # What one pass really costs a buyer, fees and tax in: each show's share
  # with its tax, our 50¢ for each show, processing once.
  def all_in_price_cents(for_rows = rows)
    items = for_rows.zip(shares(for_rows)).map do |row, share|
      { price_cents: share, discount_cents: 0, tax_cents: TaxCalculator.for_ticket(row.ticket_listing, row.ticket_tier, share).added_cents }
    end
    TicketPricing.quote(items: items, fee_mode: fee_mode(for_rows)).total_cents
  end

  # The same shows bought one at a time, fees and tax in.
  def separately_all_in_cents(for_rows = rows)
    for_rows.sum { |row| TicketPricing.all_in_price_cents(row.ticket_listing, row.ticket_tier) }
  end

  def fee_mode(for_rows = rows)
    for_rows.first&.ticket_listing&.effective_fee_mode || "buyer"
  end

  # Sales stop at the pass's own end, or when the first show's online sales
  # close, whichever is sooner.
  def closes_at(for_rows = rows)
    [ sales_end_at, *for_rows.map { |row| row.ticket_listing.off_sale_at } ].compact.min
  end

  def selling?(at = Time.current, for_rows = rows)
    status == "on_sale" && for_rows.size >= 2 &&
      (sales_start_at.nil? || sales_start_at <= at) &&
      (closes_at(for_rows).nil? || at < closes_at(for_rows)) &&
      for_rows.none? { |row| row.ticket_listing.status.in?(%w[canceled closed]) || row.ticket_listing.show.canceled }
  end

  # People who bought it (each has a ticket at every show; count the first).
  def sold_count(for_rows = rows)
    return 0 if for_rows.empty?

    tickets.where(ticket_listing_id: for_rows.first.ticket_listing_id, status: Ticket::SOLD_STATUSES).count
  end

  # How many more can sell: the fewest seats left at any show, and the cap.
  # Nil means no limit.
  def remaining(for_rows = rows)
    limits = for_rows.map { |row| row.ticket_listing.inventory.remaining(tier: row.ticket_tier) }
    limits << (max_sold - sold_count(for_rows)) if max_sold
    limits.compact.min&.clamp(0, nil)
  end

  def effective_max_per_order(for_rows = rows)
    max_per_order || for_rows.map { |row| row.ticket_listing.effective_max_per_order }.compact.min
  end

  # The picture: the pass's own wide image, else its first show's.
  def page_image_listing(for_rows = rows)
    for_rows.first&.ticket_listing
  end

  private

  def at_least_two_shows
    errors.add(:base, "A pass needs at least two shows") if pass_shows.reject(&:marked_for_destruction?).size < 2
  end

  def custom_shares_add_up
    kept = pass_shows.reject(&:marked_for_destruction?)
    total = kept.sum { |row| row.share_cents.to_i }
    return if total == price_cents

    errors.add(:base, "The shows' shares add up to #{ActiveSupport::NumberHelper.number_to_currency(total / 100.0)}, " \
                      "not the pass price of #{ActiveSupport::NumberHelper.number_to_currency(price_cents / 100.0)}")
  end
end
