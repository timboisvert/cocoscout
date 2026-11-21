# frozen_string_literal: true

# Who may see a show's ticket sales, and how much of them:
#   - the theater's managers (they have the whole module);
#   - the contractor of a contract that includes the show, and the people
#     on that contract (ContractPerson), unless the contract says not
#     (shares_ticket_sales);
#   - anyone the theater shared the show, or its whole production, with
#     (TicketSalesViewer);
#   - and, by the box office's Who sees sales settings (TicketingProfile),
#     the production's team by role and its cast.
# Only while the theater's ticketing is switched on, never for drafts.
#
# Two kinds of answer. listings_for(user) is the shares and contracts: it
# drives the My menu's Ticket Sales page and the daily email, and roles
# never join it (Tim, 2026-10-16: no Ticket Sales page for teams or cast).
# level_for(user, listing) is the whole rule, in levels:
#   :full     everything a manager reads, minus money the theater keeps and
#             buyers' emails: numbers, who's coming by name, the link
#   :numbers  sold of seats and the link
#   nil       nothing
class TicketSalesAccess
  LEVELS = %i[full numbers].freeze

  def self.listings_for(user)
    return TicketListing.none unless user

    direct = granted(TicketSalesViewer.active.where(user_id: user.id))
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

  # What a user sees of one date's sales: :full, :numbers or nil. A share or
  # a contract gives :full; otherwise their production team role, then the
  # cast rule. Nothing without Pro, with the box office closed, or for a
  # draft or canceled date.
  def self.level_for(user, listing)
    levels_for(user, [ listing ])[listing&.id]
  end

  # Several dates at once: { listing_id => level }.
  def self.levels_for(user, listings)
    listings = Array(listings).compact
    return {} if user.nil? || listings.empty?

    open = listings.select { |listing| open_for?(listing) }
    return {} if open.empty?

    shared = listings_for(user).where(id: open.map(&:id)).pluck(:id).to_set
    team = open.map(&:production).compact.uniq.to_h { |production| [ production.id, team_level(user, production) ] }
    cast_cache = {}
    open.to_h do |listing|
      level =
        if shared.include?(listing.id) then :full
        elsif (team_level = team[listing.production_id]) then team_level
        else cast_level(user, listing, cast_cache)
        end
      [ listing.id, level ]
    end
  end

  # What a user sees of a production's sales through their team role (the
  # Production Dashboard): :full or :numbers for a production team manager
  # or viewer per Who sees sales, nil for anyone else and for the
  # organization's own managers, who have the module.
  def self.team_level_for(user, production)
    return nil unless user && production && open_for_production?(production)

    team_level(user, production)
  end

  # A production team manager's comps on one date, when Who sees sales gives
  # them everything and the comp rules let the team give some:
  #   date_left   what the date can still give away, whoever gives it (nil: no limit)
  #   team_limit  the team's share of a date's comps (nil: all of them)
  #   team_given  comps the production team has already given
  #   left        what this manager can still give (nil: no limit)
  # nil for everyone else, when comps are off, and once the date has started
  # (Tim, 2026-10-17: no comps for a show that's already happened).
  # The people on a contract that includes the date have a rule of their
  # own (CompRules#contract_comps_per_show; Tim, 2026-11-17): none, or a
  # number for the date shared between all of them: the contractor, the
  # people added to the contract and, when the contract is connected to the
  # contractor's own organization, that organization's owners and managers
  # (LinkedTicketSales). For them team_limit is that number and team_given
  # what their side has given; the production team's share doesn't apply.
  def self.comp_allowance(user, listing)
    return nil unless user && listing && open_for?(listing)
    return nil if listing.show.date_and_time <= Time.current
    return nil if listing.organization.manageable_by?(user)
    return nil unless listing.effective_comps_enabled

    if on_contract_for?(user, listing) || LinkedTicketSales.manages_for?(user, listing)
      base = listing.effective_contract_comps
      return nil unless base.positive?

      # Comps approved on a request count on top (CompRequest).
      extra = listing.approved_comp_extra(:contract)
      limit = base + extra
      date_left = listing.comps_left
      given = contract_comps_given(listing)
      left = [ date_left, [ limit - given, 0 ].max ].compact.min
      return { date_left: date_left, team_limit: limit, team_given: given, left: left, contract: true, side: :contract, base: base, extra: extra }
    end

    return nil unless team_role(user, listing.production) == "manager" && team_level(user, listing.production) == :full
    return nil unless listing.effective_team_comps

    date_left = listing.comps_left
    extra = listing.approved_comp_extra(:team)
    base = (listing.effective_team_comps_per_show if listing.effective_team_comps_limit == "fixed")
    team_limit = base && (base + extra)
    team_given = team_comps_given(listing)
    left = [ date_left, (team_limit && [ team_limit - team_given, 0 ].max) ].compact.min
    { date_left: date_left, team_limit: team_limit, team_given: team_given, left: left, side: :team, base: base, extra: extra }
  end

  # Which comps someone issues from on this date: :contract (the people on
  # its contract and, connected, the people who run the contractor's
  # organization) or :team (a production team manager who sees everything).
  # nil for everyone else: the organization's own managers work from
  # Ticketing. It is who they are, not what's left: a side with nothing
  # left to issue can still change the comps it has (TicketComps).
  def self.comp_side(user, listing)
    return nil unless user && listing && open_for?(listing)
    return nil if listing.organization.manageable_by?(user)
    return :contract if on_contract_for?(user, listing) || LinkedTicketSales.manages_for?(user, listing)

    :team if team_role(user, listing.production) == "manager" && team_level(user, listing.production) == :full
  end

  # The comps on this date a side issued, whoever on it did (Tim,
  # 2026-11-17: "it doesn't matter who issued it"): order ids.
  def self.comp_ids_of(listing, side)
    scope = listing.ticket_orders.where(channel: "comp", status: TicketOrder::WAS_PAID).where.not(issued_by_id: nil)
    contract = contract_side_user_ids(listing) - manager_ids(listing)
    case side
    when :contract then scope.where(issued_by_id: contract).pluck(:id)
    when :team then scope.where.not(issued_by_id: manager_ids(listing) + contract).pluck(:id)
    else []
    end
  end

  def self.can_comp?(user, listing)
    allowance = comp_allowance(user, listing)
    allowance.present? && (allowance[:left].nil? || allowance[:left].positive?)
  end

  # Comps on this date given by the production team: by someone who is
  # neither one of the organization's managers nor on the contract's side
  # (they have their own number). Door comps carry no giver and aren't the
  # team's.
  def self.team_comps_given(listing)
    comps_given(listing).where.not(ticket_orders: { issued_by_id: manager_ids(listing) + contract_side_user_ids(listing) }).count
  end

  # Comps on this date given by the contract's side, between all of them.
  def self.contract_comps_given(listing)
    theirs = contract_side_user_ids(listing) - manager_ids(listing)
    theirs.empty? ? 0 : comps_given(listing).where(ticket_orders: { issued_by_id: theirs }).count
  end

  # Who gives comps as the contract's side for this date: the sign-ins of
  # the contractor and the contract people on every live contract that
  # includes it and shares its sales, and the owners and managers of an
  # organization such a contract is connected to.
  def self.contract_side_user_ids(listing)
    contracts = contracts_for(listing).select(&:shares_ticket_sales)
    return [] if contracts.empty?

    person_ids = contracts.filter_map { |contract| contract.contractor&.person_id } +
                 ContractPerson.where(contract_id: contracts.map(&:id)).pluck(:person_id)
    user_ids = Person.where(id: person_ids).where.not(user_id: nil).pluck(:user_id)
    ContractConnection.connected.where(contract_id: contracts.map(&:id)).includes(:linked_organization).each do |connection|
      theirs = connection.linked_organization
      user_ids += [ theirs.owner_id ] + theirs.organization_roles.where(company_role: "manager").pluck(:user_id)
    end
    user_ids.compact.uniq
  end

  def self.manager_ids(listing)
    org = listing.organization
    org.organization_roles.where(company_role: "manager").pluck(:user_id) + [ org.owner_id ]
  end
  private_class_method :manager_ids

  # Every comp ticket on the date that someone gave (not the door's).
  def self.comps_given(listing)
    Ticket.joins(:ticket_order).where(ticket_listing_id: listing.id, status: Ticket::SOLD_STATUSES)
          .where(ticket_orders: { channel: "comp", status: TicketOrder::WAS_PAID })
          .where.not(ticket_orders: { issued_by_id: nil })
  end
  private_class_method :comps_given

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
    granted(TicketSalesViewer.active).where(organization_id: production.organization_id)
                     .where("(scope_type = 'TicketListing' AND scope_id IN (:l)) OR (scope_type = 'Production' AND scope_id = :p)",
                            l: listing_ids, p: production.id)
                     .preload(:user).order(:created_at)
  end

  # Everyone the show was shared with, directly or through its production.
  def self.viewers_for(listing)
    granted(TicketSalesViewer.active).where(organization_id: listing.organization_id)
                     .where("(scope_type = 'TicketListing' AND scope_id = :l) OR (scope_type = 'Production' AND scope_id = :p)",
                            l: listing.id, p: listing.production_id)
                     .preload(:user).order(:created_at)
  end

  # The productions a user sees through a contract (their own shows), for a
  # share row to hang a daily-email choice on.
  def self.contract_productions(user)
    return [] unless user

    sharing_contracts(user).includes(:production).filter_map(&:production).uniq
  end

  # Whether the user is on a contract that includes this date and shares its
  # sales: the contractor's person, or a contract person.
  def self.on_contract_for?(user, listing)
    return false unless user && listing

    contract_show_ids(user).include?(listing.show_id)
  end

  # The live contracts the user is on (Contract.visible_to) that share their
  # ticket sales.
  def self.sharing_contracts(user)
    Contract.visible_to(user).where(shares_ticket_sales: true).where.not(status: %w[draft cancelled])
  end
  private_class_method :sharing_contracts

  # The user's role on a production's team, found through the production's
  # own organization (not Current.organization: the My pages have none):
  # their ProductionPermission, else their manager or viewer role across the
  # organization. "member" is no role of its own.
  def self.team_role(user, production)
    permission = user.production_permissions.find_by(production_id: production.id)
    return permission.role if permission

    role = user.organization_roles.find_by(organization_id: production.organization_id)&.company_role
    role == "member" ? nil : role
  end

  def self.team_level(user, production)
    return nil if production.organization.manageable_by?(user)

    role = team_role(user, production)
    role && production.organization.ticketing_profile&.team_level(role)
  end
  private_class_method :team_level

  # The cast rule for one date: everyone on the production (production_cast:
  # in its talent pool, or cast in any of its dates), or only the people
  # cast in that show (show_cast), for any of the user's people or groups.
  # Someone cast in the date who isn't in the pool counts either way.
  def self.cast_level(user, listing, cache = {})
    level = listing.organization.ticketing_profile&.cast_level
    return nil unless level

    people_ids = cache[:people_ids] ||= user.people.pluck(:id)
    group_ids = cache[:group_ids] ||= GroupMembership.where(person_id: people_ids).distinct.pluck(:group_id)
    return nil if people_ids.empty? && group_ids.empty?

    cast = ShowPersonRoleAssignment.visible_to_performers.where(show_id: listing.show_id)
                                   .where("(assignable_type = 'Person' AND assignable_id IN (:p)) OR (assignable_type = 'Group' AND assignable_id IN (:g))",
                                          p: people_ids.presence || [ 0 ], g: group_ids.presence || [ 0 ]).exists?
    return level if cast
    return nil if listing.organization.ticketing_profile.cast_sales == "show_cast"

    on_production = cache[[ :production, listing.production_id ]] ||= begin
      pool = listing.production.effective_talent_pool
      in_pool = pool.present? && TalentPoolMembership.where(talent_pool_id: pool.id)
                                                     .where("(member_type = 'Person' AND member_id IN (:p)) OR (member_type = 'Group' AND member_id IN (:g))",
                                                            p: people_ids.presence || [ 0 ], g: group_ids.presence || [ 0 ]).exists?
      in_pool || ShowPersonRoleAssignment.visible_to_performers.where(shows: { production_id: listing.production_id })
                                         .where("(assignable_type = 'Person' AND assignable_id IN (:p)) OR (assignable_type = 'Group' AND assignable_id IN (:g))",
                                                p: people_ids.presence || [ 0 ], g: group_ids.presence || [ 0 ]).exists?
    end
    level if on_production
  end
  private_class_method :cast_level

  # Pro, box office open, date live (not a draft, not canceled).
  def self.open_for?(listing)
    return false if listing.status.in?(%w[draft canceled])
    return false if listing.show.nil? || listing.show.canceled

    open_for_production?(listing.production)
  end
  private_class_method :open_for?

  def self.open_for_production?(production)
    org = production&.organization
    org.present? && org.feature_available?(:ticketing) && org.ticketing_profile&.enabled? == true
  end
  private_class_method :open_for_production?

  # Shares the theater made (a manager's grant or invitation). The row
  # My::TicketSalesController#daily_email makes for a contract-only producer
  # has no granter: it holds their email choice and shares nothing — a
  # contractor sees only their contract's shows, and only while it says so.
  def self.granted(viewers)
    viewers.where.not(granted_by_id: nil)
  end
  private_class_method :granted

  def self.contract_show_ids(user)
    sharing_contracts(user).flat_map { |contract| contract.contract_shows.pluck(:id) }
  end
  private_class_method :contract_show_ids
end
