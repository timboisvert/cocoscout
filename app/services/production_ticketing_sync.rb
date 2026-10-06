# frozen_string_literal: true

# Keeps each show's ticket types in step with its production's
# (ProductionTicketing) while the show inherits them: the same names, prices,
# seats, descriptions, hidden codes and order. A type the production drops
# goes from its shows too (kept, archived, only where a ticket was sold on
# it, so that ticket keeps its type). A
# new price applies to sales from now on; tickets already sold keep the price
# they were bought at.
#
# A show with its own prices (inherits_tiers false) is left alone.
class ProductionTicketingSync
  SYNCED = %w[name price_cents quantity admits description position hidden unlock_code min_per_order max_per_order].freeze

  Result = Data.define(:updated, :skipped)

  # Every inheriting show of the production.
  def self.sync_all!(production_ticketing)
    skipped = []
    sources = sources_for(production_ticketing)
    listings = production_ticketing.listings.where(inherits_tiers: true).where.not(status: "canceled").includes(:ticket_tiers).to_a
    listings.each { |listing| skipped.concat(sync!(listing, production_ticketing, sources: sources)) }
    Result.new(updated: listings.size, skipped: skipped)
  end

  # Always read fresh: a setup's loaded tiers can be out of date by the time
  # it's saved.
  def self.sources_for(production_ticketing)
    TicketTier.where(production_ticketing_id: production_ticketing.id).order(:position, :id).to_a
  end

  # One show. Returns the copies that couldn't take a change (seats below
  # what that show already sold), which keep their old values.
  def self.sync!(listing, production_ticketing = listing.production_ticketing, sources: nil)
    return [] unless production_ticketing && listing.inherits_tiers

    skipped = []
    sources ||= sources_for(production_ticketing)
    copies = listing.ticket_tiers.to_a.index_by(&:source_tier_id)
    TicketTier.transaction do
      sources.each do |source|
        attrs = source.attributes.slice(*SYNCED).merge("archived_at" => source.archived_at)
        copy = copies.delete(source.id)
        if copy
          unless copy.update(attrs)
            # Seats would drop below what this date sold: keep its seats,
            # take everything else.
            copy.reload.update!(attrs.except("quantity"))
            skipped << copy
          end
        else
          listing.ticket_tiers.create!(attrs.merge("source_tier_id" => source.id))
        end
      end
      # Types the production no longer has (or a show's own leftovers): gone,
      # unless a ticket was sold on one.
      copies.each_value(&:retire!)
    end
    skipped
  end
end
