# frozen_string_literal: true

# Keeps a production's listings matching its ticketing setup, the way
# sign-ups keep a repeating form's events (EventAssociationService):
#
#   - every show the setup includes (ProductionTicketing#matching_shows) gets a
#     listing, on sale from the setup's schedule, inheriting its ticket types;
#   - a listing whose show no longer matches is removed if nobody has bought
#     for it, and kept (and reported) if anyone has, so a change of settings
#     never strands a buyer;
#   - shows that already had a listing of their own (made by hand or from a
#     contract) are left exactly as they are.
#
# Run hourly, when a show is added, and when the setup is saved. Nothing
# happens while the setup is switched off.
class ProductionTicketingDates
  Result = Data.define(:added, :removed, :kept) do
    def summary
      [ ("#{added.size} #{added.one? ? 'date' : 'dates'} added" if added.any?),
        ("#{removed.size} removed" if removed.any?) ].compact.join(", ")
    end
  end

  def self.sync_all!
    ProductionTicketing.where(enabled: true).includes(:production).find_each do |production_ticketing|
      sync!(production_ticketing)
    rescue StandardError => e
      Rails.logger.error("[ProductionTicketingDates] production #{production_ticketing.production_id}: #{e.class}: #{e.message}")
    end
  end

  def self.sync!(production_ticketing)
    return Result.new(added: [], removed: [], kept: []) unless production_ticketing.enabled?

    matching = production_ticketing.matching_shows.to_a
    matching_ids = matching.map(&:id).to_set
    listed_show_ids = TicketListing.where(show_id: matching_ids.to_a).pluck(:show_id).to_set
    has_tiers = TicketTier.where(production_ticketing_id: production_ticketing.id).exists?

    added = has_tiers ? matching.reject { |show| listed_show_ids.include?(show.id) }.filter_map { |show| add!(production_ticketing, show) } : []

    removed = []
    kept = []
    production_ticketing.listings.where(inherits_tiers: true).where.not(status: "canceled")
                        .joins(:show).where("shows.date_and_time > ?", Time.current).includes(:show).find_each do |listing|
      next if matching_ids.include?(listing.show_id)

      if listing.ticket_orders.exists?
        kept << listing
      else
        listing.destroy!
        removed << listing
      end
    end
    Result.new(added: added, removed: removed, kept: kept)
  end

  # Switching the production off stops its dates selling (the ones following
  # its setup; a date with its own prices is the manager's to pause). On
  # again, they resume (and a sync! adds any newly matching dates).
  def self.switch!(production_ticketing, on:)
    inheriting = production_ticketing.listings.where(inherits_tiers: true)
    if on
      inheriting.where(status: "paused").update_all(status: "on_sale", updated_at: Time.current)
    else
      inheriting.where(status: "on_sale").update_all(status: "paused", updated_at: Time.current)
    end
  end

  # Inheriting shows still on the old schedule move to the new one; a show
  # given its own sales window keeps it.
  def self.reschedule!(production_ticketing, was:)
    production_ticketing.listings.where(inherits_tiers: true).includes(:show).find_each do |listing|
      starts_at = listing.show.date_and_time
      changes = {}
      changes[:on_sale_at] = production_ticketing.on_sale_at_for(starts_at) if listing.on_sale_at == was.on_sale_at_for(starts_at)
      changes[:off_sale_at] = production_ticketing.off_sale_at_for(starts_at) if listing.off_sale_at == was.off_sale_at_for(starts_at)
      listing.update_columns(changes.merge(updated_at: Time.current)) if changes.any?
    end
  end

  def self.add!(production_ticketing, show)
    TicketListing.transaction do
      listing = TicketListing.create!(show: show, status: "on_sale", inherits_tiers: true,
                                      on_sale_at: production_ticketing.on_sale_at_for(show.date_and_time),
                                      off_sale_at: production_ticketing.off_sale_at_for(show.date_and_time))
      ProductionTicketingSync.sync!(listing, production_ticketing)
      listing
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn("[ProductionTicketingDates] show #{show.id}: #{e.message}")
    nil
  end

  private_class_method :add!
end
