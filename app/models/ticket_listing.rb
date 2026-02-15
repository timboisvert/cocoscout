# frozen_string_literal: true

class TicketListing < ApplicationRecord
  belongs_to :show_ticketing
  belongs_to :ticketing_provider

  has_many :ticket_offers, dependent: :destroy
  has_many :ticket_sales, through: :ticket_offers

  enum :status, {
    draft: "draft",
    published: "published",
    paused: "paused",
    ended: "ended"
  }, default: :draft, prefix: true

  validates :show_ticketing_id, uniqueness: { scope: :ticketing_provider_id }

  scope :active, -> { where(status: %w[published paused]) }
  scope :published, -> { status_published }

  accepts_nested_attributes_for :ticket_offers, allow_destroy: true

  # Sync with external provider
  def sync!
    return unless ticketing_provider.configured?

    adapter = ticketing_provider.adapter
    result = adapter.sync_listing(self)

    if result[:success]
      update!(
        last_synced_at: Time.current,
        sync_errors: []
      )
    else
      add_sync_error(result[:error])
    end

    result
  end

  # Publish to external provider
  def publish!
    return unless status_draft?
    return unless ticketing_provider.configured?

    adapter = ticketing_provider.adapter
    result = adapter.create_event(self)

    if result[:success]
      update!(
        status: :published,
        external_event_id: result[:event_id],
        external_url: result[:event_url],
        published_at: Time.current,
        last_synced_at: Time.current
      )
    else
      add_sync_error(result[:error])
    end

    result
  end

  # Update external provider with current inventory
  def push_inventory!
    return unless status_published?
    return unless ticketing_provider.configured?

    adapter = ticketing_provider.adapter
    result = adapter.update_inventory(self)

    if result[:success]
      update!(last_synced_at: Time.current, sync_errors: [])
    else
      add_sync_error(result[:error])
    end

    result
  end

  # Pull sales from external provider
  def pull_sales!
    return unless status_published?
    return unless ticketing_provider.configured?

    adapter = ticketing_provider.adapter
    result = adapter.fetch_sales(self)

    if result[:success]
      process_sales(result[:sales])
      update!(last_synced_at: Time.current, sync_errors: [])
    else
      add_sync_error(result[:error])
    end

    result
  end

  # Display name
  def display_name
    "#{show_ticketing.show.display_name} on #{ticketing_provider.name}"
  end

  # Provider display name
  def provider_name
    ticketing_provider.name
  end

  private

  def add_sync_error(error)
    errors_list = sync_errors || []
    errors_list << {
      message: error,
      at: Time.current.iso8601
    }
    # Keep only last 10 errors
    errors_list = errors_list.last(10)
    update!(sync_errors: errors_list)
  end

  def process_sales(sales_data)
    sales_data.each do |sale_data|
      offer = ticket_offers.find_by(external_offer_id: sale_data[:offer_id])
      next unless offer

      # Skip if already recorded
      next if offer.ticket_sales.exists?(external_sale_id: sale_data[:sale_id])

      # Create sale record
      sale = offer.ticket_sales.create!(
        show_ticket_tier: offer.show_ticket_tier,
        external_sale_id: sale_data[:sale_id],
        quantity: sale_data[:quantity],
        total_seats: sale_data[:quantity] * offer.seats_per_offer,
        total_cents: sale_data[:total_cents],
        customer_name: sale_data[:customer_name],
        customer_email: sale_data[:customer_email],
        customer_phone: sale_data[:customer_phone],
        purchased_at: sale_data[:purchased_at],
        synced_at: Time.current
      )

      # Update tier availability
      show_ticketing.process_sale!(offer.show_ticket_tier_id, sale.total_seats)
    end
  end
end
