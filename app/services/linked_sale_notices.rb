# frozen_string_literal: true

# Ticket sales as they happen, for the other side of a connected contract
# (Tim, 2026-11-17). The organization that sells the tickets has its own
# notices (TicketingNotifier, by plan). Through the connection, the
# contractor's organization chooses, person by person, who on its side is
# notified of each online sale and each comp for the contract's dates. A
# notification and a push, never an email, and counts only: how many, for
# which date, and how full it is now. No buyer's name.
#
# Who can be chosen is who can already see those sales, never the cast:
# the organization's owner and managers, the production's team, and the
# people on the contract. Everyone starts off. Someone who is chosen finds
# a switch in their own account and can turn it off, and back on.
# It all stops when the seller stops sharing the contract's sales.
class LinkedSaleNotices
  Candidate = Data.define(:user, :name, :role)
  # Which ways of selling tell them (TicketingAfterSaleJob::NOTICES): an
  # online sale and a comp. Door sales on the night aren't sent.
  KINDS = { sale: "linked_ticket_sale", comp_issued: "linked_ticket_comp" }.freeze

  class << self
    # Everyone who could be notified for a connection, with what they are
    # there, in the order: runs the organization, production team, on the
    # contract.
    def candidates(connection)
      theirs = connection.linked_organization
      seen = Set.new
      out = []
      add = lambda do |user, role|
        next if user.nil? || seen.include?(user.id)

        seen << user.id
        out << Candidate.new(user: user, name: (user.default_person&.name || user.people.first&.name || user.email_address), role: role)
      end
      add.call(theirs.owner, "Owner")
      User.where(id: theirs.organization_roles.where(company_role: "manager").select(:user_id)).each { |user| add.call(user, "Manager") }
      if connection.linked_production
        ProductionPermission.where(production_id: connection.linked_production_id).includes(:user).each do |permission|
          role = permission.role == "manager" ? "Production team manager" : "Production team viewer"
          add.call(permission.user, role) if connection.team_level(permission.role)
        end
      end
      contract = connection.contract
      people = [ contract.contractor&.person ] + Person.where(id: ContractPerson.where(contract_id: contract.id).select(:person_id)).to_a
      people.compact.each { |person| add.call(person.user, "On the contract") }
      out
    end

    # The contractor's organization's choice: exactly these people are
    # chosen. Someone already chosen keeps their own switch; someone taken
    # off is removed.
    def choose!(connection, user_ids, by:)
      allowed = candidates(connection).map { |candidate| candidate.user.id }
      wanted = Array(user_ids).map(&:to_i) & allowed
      ContractConnectionWatcher.transaction do
        connection.watchers.where.not(user_id: wanted).destroy_all
        (wanted - connection.watchers.pluck(:user_id)).each { |id| connection.watchers.create!(user_id: id, enabled_by: by) }
      end
      connection.watchers.reload
    end

    # A person's own switches: every connection they were chosen for that
    # is still connected.
    def switches_for(user)
      ContractConnectionWatcher.where(user_id: user.id).joins(:contract_connection).where(contract_connections: { status: "connected" })
                               .includes(contract_connection: [ :organization, :linked_organization, :linked_production, { contract: :production } ])
                               .order(:id)
    end

    # They switched theirs on or off.
    def set_muted!(user, watcher_id, muted)
      watcher = ContractConnectionWatcher.find_by(id: watcher_id, user_id: user.id) or return
      watcher.update!(muted_at: muted ? (watcher.muted_at || Time.current) : nil)
    end

    # After a sale or comps on the seller's listing (TicketingAfterSaleJob):
    # tell whoever is listening on a connection that carries this date.
    # `orders`: the order, or every order of one go of comps.
    def after_sale(kind, orders)
      template = KINDS[kind] or return
      orders = Array(orders).compact
      listing = orders.first&.ticket_listing
      show = listing&.show
      contract_id = show&.space_rental_id && SpaceRental.where(id: show.space_rental_id).pick(:contract_id)
      return unless contract_id

      ContractConnection.connected.where(contract_id: contract_id).includes(:contract, :linked_organization, :linked_production).each do |connection|
        next unless LinkedTicketSales.sharing?(connection) && LinkedTicketSales.open?(listing)

        variables = variables_for(connection, listing, orders, kind)
        connection.watchers.listening.includes(:user).each do |watcher|
          next unless still_allowed?(watcher.user, connection)

          Notifier.deliver(user: watcher.user, category: "ticketing_sales", kind: template, template_key: template,
                           variables: variables, path: path_for(watcher.user, connection, listing),
                           organization: connection.linked_organization, subject: orders.first)
        end
      end
    rescue StandardError => e
      # A notice that can't be sent never fails the sale's own notices.
      Rails.logger.error("[LinkedSaleNotices] #{kind}: #{e.class}: #{e.message}")
      nil
    end

    private

    # Chosen once, still someone who may see the sales now.
    def still_allowed?(user, connection)
      candidates(connection).any? { |candidate| candidate.user.id == user.id }
    end

    def variables_for(connection, listing, orders, kind)
      count = orders.sum { |order| order.tickets.count { |ticket| Ticket::SOLD_STATUSES.include?(ticket.status) } }
      seller = connection.organization
      zone = Time.find_zone(seller.time_zone.presence) || Time.zone
      stats = Ticketing::ListingStats.of(listing)
      noun = kind == :comp_issued ? "comp" : "ticket"
      { ticket_count: ActionController::Base.helpers.pluralize(count, noun),
        production_name: connection.production_name.presence || listing.production&.name.to_s,
        show_date: listing.show.date_and_time.in_time_zone(zone).strftime("%a %b %-d"),
        sold_line: stats.sold_words, organization_name: seller.name,
        contractor_name: "", linked_organization_name: connection.linked_organization.name, linked_production_name: connection.production_name.to_s, note: "" }
    end

    # Inside their organization when they can open it; else on My.
    def path_for(user, connection, listing)
      routes = Rails.application.routes.url_helpers
      theirs = connection.linked_organization
      inside = theirs.owner_id == user.id || theirs.organization_roles.exists?(user_id: user.id) ||
               (connection.linked_production && user.production_permissions.exists?(production_id: connection.linked_production_id))
      if inside && connection.linked_production
        routes.manage_production_sale_path(connection.linked_production, listing)
      else
        routes.my_ticket_sale_path(listing)
      end
    end
  end
end
