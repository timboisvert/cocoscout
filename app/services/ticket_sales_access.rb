# frozen_string_literal: true

# Who may see a show's ticket sales (read-only, names only):
#   - the theater's managers (they have the whole module);
#   - the contractor of a contract that includes the show, unless the
#     contract says not (shares_ticket_sales);
#   - anyone the theater shared the show, or its whole production, with
#     (TicketSalesViewer).
# Only while the theater's ticketing is switched on, never for drafts.
class TicketSalesAccess
  def self.listings_for(user)
    return TicketListing.none unless user

    direct = TicketSalesViewer.active.where(user_id: user.id)
    listing_ids = direct.where(scope_type: "TicketListing").pluck(:scope_id)
    production_ids = direct.where(scope_type: "Production").pluck(:scope_id)
    show_ids = contract_show_ids(user)

    TicketListing.joins(organization: :ticketing_profile).joins(:show)
                 .where(ticketing_profiles: { enabled: true })
                 .where.not(status: "draft")
                 .where("ticket_listings.id IN (:l) OR ticket_listings.production_id IN (:p) OR ticket_listings.show_id IN (:s)",
                        l: listing_ids.presence || [ 0 ], p: production_ids.presence || [ 0 ], s: show_ids.presence || [ 0 ])
  end

  def self.can_see?(user, listing)
    listings_for(user).exists?(id: listing.id)
  end

  # The contracts whose contractor sees this show's sales automatically.
  def self.contracts_for(listing)
    Contract.where(organization_id: listing.organization_id).where.not(status: %w[draft cancelled])
            .includes(contractor: :person).select { |contract| contract.contract_shows.exists?(id: listing.show_id) }
  end

  # The contracts of a production whose contractor sees its shows' sales.
  def self.contracts_for_production(production)
    Contract.where(organization_id: production.organization_id, production_id: production.id).where.not(status: %w[draft cancelled])
            .includes(contractor: :person).to_a
  end

  # Everyone a production was shared with: every date, or any one of its dates.
  def self.viewers_for_production(production)
    listing_ids = TicketListing.where(production_id: production.id).select(:id)
    TicketSalesViewer.active.where(organization_id: production.organization_id)
                     .where("(scope_type = 'TicketListing' AND scope_id IN (:l)) OR (scope_type = 'Production' AND scope_id = :p)",
                            l: listing_ids, p: production.id)
                     .preload(:user).order(:created_at)
  end

  # Everyone the show was shared with, directly or through its production.
  def self.viewers_for(listing)
    TicketSalesViewer.active.where(organization_id: listing.organization_id)
                     .where("(scope_type = 'TicketListing' AND scope_id = :l) OR (scope_type = 'Production' AND scope_id = :p)",
                            l: listing.id, p: listing.production_id)
                     .preload(:user).order(:created_at)
  end

  # The productions a user sees through a contract (their own shows), for a
  # share row to hang a daily-email choice on.
  def self.contract_productions(user)
    return [] unless user

    people_ids = user.people.select(:id)
    Contract.joins(:contractor).where(contractors: { person_id: people_ids }).where(shares_ticket_sales: true)
            .where.not(status: %w[draft cancelled]).includes(:production).filter_map(&:production).uniq
  end

  def self.contract_show_ids(user)
    people_ids = user.people.select(:id)
    Contract.joins(:contractor).where(contractors: { person_id: people_ids }).where(shares_ticket_sales: true)
            .where.not(status: %w[draft cancelled]).flat_map { |contract| contract.contract_shows.pluck(:id) }
  end
  private_class_method :contract_show_ids
end
