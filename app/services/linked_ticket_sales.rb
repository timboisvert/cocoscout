# frozen_string_literal: true

# Ticket sales for a date that follows another organization's contract date
# (Show#linked_show; ContractConnection). The tickets are sold by the
# organization that wrote the contract, from its own box office; the
# contractor's organization sees them read-only, one layer down
# (Tim, 2026-11-16):
#   - its owners and managers see what the contractor sees (:full: numbers,
#     who's coming by name, the link; never what the seller keeps or buyers'
#     emails);
#   - its production team and cast see what the connection says
#     (team_manager_sales, team_viewer_sales, cast_sales: the box office's
#     own three choices), and the cast never more than :numbers.
# All of it only while the seller shares the contract's sales
# (contracts.shares_ticket_sales): that one switch stops every layer.
class LinkedTicketSales
  # The live connection a linked date arrived through, or nil.
  def self.connection_for(show)
    seller_show = show&.linked_show
    rental = seller_show&.space_rental
    return nil unless rental

    ContractConnection.connected.find_by(contract_id: rental.contract_id, linked_production_id: show.production_id)
  end

  # The live connections that bring another organization's dates into this
  # production.
  def self.connections_for_production(production)
    return ContractConnection.none unless production

    ContractConnection.connected.where(linked_production_id: production.id).includes(:organization, :contract)
  end

  # The seller's listing for a linked date, when its sales are open to the
  # contractor's side: connected, shared, on Pro with the box office open,
  # and the date live.
  def self.listing_for(show, connection: connection_for(show))
    return nil unless connection && sharing?(connection)

    listing = show.linked_show&.ticket_listing
    listing if listing && open?(listing)
  end

  # What a user sees of a linked date's sales in the contractor's
  # organization: :full, :numbers or nil.
  def self.level_for(user, show, connection: connection_for(show))
    return nil unless user && connection && listing_for(show, connection: connection)

    level_in(user, connection, show: show)
  end

  # The same question for the whole production (its ticket sales page): the
  # most a user sees of any of its linked dates.
  def self.production_level(user, production)
    return nil unless user && production

    connections_for_production(production).select { |connection| sharing?(connection) }
                                          .filter_map { |connection| level_in(user, connection, show: nil) }
                                          .min_by { |level| level == :full ? 0 : 1 }
  end

  # The seller's listings behind a production's linked dates, live ones only.
  def self.listings_for_production(production)
    connections = connections_for_production(production).select { |connection| sharing?(connection) }
    seller_show_ids = Show.where(production_id: production.id).where.not(linked_show_id: nil)
                          .joins("INNER JOIN shows seller_shows ON seller_shows.id = shows.linked_show_id")
                          .joins("INNER JOIN space_rentals ON space_rentals.id = seller_shows.space_rental_id")
                          .where(space_rentals: { contract_id: connections.map(&:contract_id) })
                          .select(:linked_show_id)
    TicketListing.where(show_id: seller_show_ids).where.not(status: %w[draft canceled])
                 .joins(:show).where(shows: { canceled: false })
                 .select { |listing| open?(listing) }
                 .then { |listings| TicketListing.where(id: listings.map(&:id)).joins(:show) }
  end

  # For the organization that sells: who on the other side sees its sales,
  # in a sentence. Names for the full view, a count for the rest.
  def self.viewer_words(connection)
    return "Nobody, because ticket sales aren't shared for this contract." unless connection.contract.shares_ticket_sales

    theirs = connection.linked_organization
    full = User.where(id: [ theirs.owner_id ] + theirs.organization_roles.where(company_role: "manager").pluck(:user_id))
               .filter_map { |user| user.default_person&.name || user.people.first&.name }.uniq
    words = "#{full.presence&.to_sentence || "The owners and managers of #{theirs.name}"} can see ticket sales for these dates, just as a contractor on the contract can."
    below = [ ("its production team" unless connection.team_manager_sales == "nothing" && connection.team_viewer_sales == "nothing"),
              ("its cast" unless connection.cast_sales == "nothing") ].compact
    below.any? ? "#{words} #{theirs.name} decides how much of that #{below.to_sentence} can see, and the cast is never shown more than how many tickets have sold." : words
  end

  def self.sharing?(connection)
    connection.connected? && connection.contract.shares_ticket_sales
  end

  # Pro, box office open, date live: TicketSalesAccess's own rule, read here
  # for the seller.
  def self.open?(listing)
    return false if listing.status.in?(%w[draft canceled])
    return false if listing.show.nil? || listing.show.canceled

    seller = listing.organization
    seller.feature_available?(:ticketing) && seller.ticketing_profile&.enabled? == true
  end

  def self.level_in(user, connection, show:)
    theirs = connection.linked_organization
    return :full if user.superadmin? || theirs.manageable_by?(user)
    return :full if ContractConnections.contractor?(user, connection.contract)

    production = connection.linked_production
    role = team_role(user, production)
    return connection.team_level(role) if role && connection.team_level(role)

    cast_level(user, connection, production, show)
  end
  private_class_method :level_in

  # Their role on the production's team: their own permission on it, else a
  # viewer's role across the organization (TicketSalesAccess.team_role).
  def self.team_role(user, production)
    return nil unless production

    permission = user.production_permissions.find_by(production_id: production.id)
    return permission.role if permission

    role = user.organization_roles.find_by(organization_id: production.organization_id)&.company_role
    role == "member" ? nil : role
  end
  private_class_method :team_role

  # The cast rule, on the contractor's own production: everyone on it (its
  # talent pool, or cast in any of its dates), or only that date's cast.
  def self.cast_level(user, connection, production, show)
    level = connection.cast_level
    return nil unless level && production

    people_ids = user.people.pluck(:id)
    group_ids = GroupMembership.where(person_id: people_ids).distinct.pluck(:group_id)
    return nil if people_ids.empty? && group_ids.empty?

    theirs = "(assignable_type = 'Person' AND assignable_id IN (:p)) OR (assignable_type = 'Group' AND assignable_id IN (:g))"
    binds = { p: people_ids.presence || [ 0 ], g: group_ids.presence || [ 0 ] }
    in_this_date = show && ShowPersonRoleAssignment.visible_to_performers.where(show_id: show.id).where(theirs, binds).exists?
    return level if in_this_date
    return nil if connection.cast_sales == "show_cast"

    pool = production.effective_talent_pool
    in_pool = pool.present? && TalentPoolMembership.where(talent_pool_id: pool.id)
                                                   .where("(member_type = 'Person' AND member_id IN (:p)) OR (member_type = 'Group' AND member_id IN (:g))", binds).exists?
    in_any_date = ShowPersonRoleAssignment.visible_to_performers.joins(:show).where(shows: { production_id: production.id }).where(theirs, binds).exists?
    level if in_pool || in_any_date
  end
  private_class_method :cast_level
end
