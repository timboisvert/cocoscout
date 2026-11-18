# frozen_string_literal: true

# Followers through the contract (Tim, 2026-11-17). An organization keeps a
# mailing list for a contractor's shows (MailingList#contractor); its box is
# on the checkout of every production under a live contract with them, and
# the list is shared with everyone on those contracts: the contractor and
# the people added to the contract. Everyone on the list is shared, however
# they came to be on it (Tim: "if it's on that list, it got on there for a
# reason").
#
# Where they see it follows one rule:
#   - a contract that isn't connected to an organization of their own, or
#     is connected to one they don't run: on My, in My Followers. They look,
#     search, download and copy. Nothing is sent from there.
#   - a contract connected to an organization they run: in that
#     organization. On the free plan, a read-only page (the same four
#     things). On Pro, the followers are added to the organization's own
#     followers, on a list of its own (sync!), and it emails them from its
#     own allowance.
#
# A window (My, a free organization) shows only people still following the
# sharing organization's list and never bounced or complained anywhere.
class SharedFollowers
  Row = Struct.new(:name, :email, :joined_at, :from, keyword_init: true)

  # The contracts through which a user is shared anything: the ones they're
  # on, live or finished. A finished contract keeps its followers (they
  # asked to hear about the contractor's shows); a draft or a canceled one
  # shares nothing.
  def self.contracts_for(user)
    return Contract.none unless user

    Contract.visible_to(user).where(status: %w[active completed])
  end

  # Every list shared with a user through a contract they're on.
  def self.lists_for(user)
    contracts = contracts_for(user)
    return MailingList.none unless contracts.exists?

    MailingList.active.where(shared_with_contractor: true, source_list_id: nil)
               .where(contractor_id: contracts.select(:contractor_id))
               .includes(:organization, :contractor).order(:name)
  end

  # The organization of the user's own that a list has moved into, if any:
  # one they run, connected to a contract with the list's contractor.
  def self.home_organization(user, list)
    managed = ContractConnections.managed_organization_ids(user)
    return nil if managed.empty?

    ContractConnection.connected.where(organization_id: list.organization_id, linked_organization_id: managed)
                      .where(contract_id: contracts_for(user).where(contractor_id: list.contractor_id).select(:id))
                      .includes(:linked_organization).order(:answered_at).first&.linked_organization
  end

  # The lists a user sees on My: the ones that haven't moved into an
  # organization they run.
  def self.my_lists(user)
    lists_for(user).reject { |list| home_organization(user, list) }
  end

  # ...and the ones that have, with where: [[list, organization], ...].
  def self.moved_lists(user)
    lists_for(user).filter_map { |list| (home = home_organization(user, list)) && [ list, home ] }
  end

  # The lists shared with an organization: a contract with the list's
  # contractor is connected to it.
  def self.lists_for_organization(organization)
    return MailingList.none unless organization

    contractors = Contract.where(id: ContractConnection.connected.where(linked_organization_id: organization.id).select(:contract_id))
                          .select(:contractor_id)
    MailingList.active.where(shared_with_contractor: true, source_list_id: nil, contractor_id: contractors)
               .where.not(organization_id: organization.id).includes(:organization, :contractor).order(:name)
  end

  # Whether a user is shared a list at all (the door to every window).
  def self.shared_with?(user, list)
    list&.shared? && lists_for(user).exists?(id: list.id)
  end

  def self.count(list)
    list.followers.emailable.count
  end

  # Everyone on a list who is still following, newest first, with when they
  # joined and how. `q` narrows by name or email.
  def self.rows(list, q: nil, limit: nil)
    scope = list.mailing_list_memberships.joins(:follower).merge(Follower.emailable)
                .includes(follower: { follower_sources: :production }).order(created_at: :desc)
    if q.present?
      needle = "%#{Follower.sanitize_sql_like(q.to_s.strip)}%"
      scope = scope.where("followers.email ILIKE :q OR followers.name ILIKE :q", q: needle)
    end
    scope = scope.limit(limit) if limit
    productions = list.contract_productions.pluck(:id) | list.mailing_list_productions.pluck(:production_id)
    scope.map do |membership|
      follower = membership.follower
      Row.new(name: follower.name, email: follower.email, joined_at: membership.created_at,
              from: from_words(follower, list, productions))
    end
  end

  # "Tickets · The Holly Problem · Dec 18", or "Added by Stars & Garters".
  def self.from_words(follower, list, production_ids)
    ticket = follower.follower_sources.select { |source| source.kind == "checkout" && production_ids.include?(source.production_id) }
                     .max_by(&:occurred_at)
    return [ "Tickets", ticket.production&.name ].compact.join(" · ") if ticket

    "Added by #{list.organization.name}"
  end

  # The list as a spreadsheet.
  def self.csv(list)
    require "csv"
    CSV.generate do |csv|
      csv << [ "Name", "Email", "Joined", "From" ]
      rows(list).each { |row| csv << [ row.name, row.email, row.joined_at.strftime("%Y-%m-%d"), row.from ] }
    end
  end

  # ---- A Pro organization's own copy ----------------------------------

  # The organization's own list for a shared one, made the first time.
  def self.received_list!(organization, list)
    organization.mailing_lists.find_by(source_list_id: list.id) ||
      organization.mailing_lists.create!(kind: "group", source_list: list, name: "From #{list.organization.name}")
  end

  # Brings a Pro organization's copies up to date: everyone still following
  # each list shared with it becomes its own follower, on its own list for
  # that source. Someone who unsubscribed from this organization, or
  # bounced, is never re-added; someone it already had is only put on the
  # list. Nobody is ever taken off: once they're its followers, they stay
  # until they say otherwise. Safe to run again. Returns how many it added.
  def self.sync!(organization)
    return 0 unless organization&.feature_available?(:mailing_lists)

    added = 0
    lists_for_organization(organization).each do |list|
      target = received_list!(organization, list)
      target.update!(archived_at: nil) if target.archived?
      have = target.followers.pluck(:email).to_set
      list.mailing_list_memberships.joins(:follower).merge(Follower.emailable).includes(:follower).find_each do |membership|
        source = membership.follower
        next if have.include?(source.email)

        Follower.transaction do
          mine = Follower.for!(organization, source.email, name: source.name)
          next unless mine.subscribed?

          target.mailing_list_memberships.find_or_create_by!(follower: mine)
          mine.follower_sources.create!(kind: "shared", mailing_list: target, occurred_at: membership.created_at)
          added += 1
        end
      end
    end
    added
  end

  # A list changed (someone joined it): bring every Pro organization it's
  # shared with up to date.
  def self.sync_list!(list)
    return unless list&.shared?

    Organization.where(id: ContractConnection.connected
                                             .where(contract_id: Contract.where(contractor_id: list.contractor_id).select(:id))
                                             .select(:linked_organization_id))
                .find_each { |organization| sync!(organization) }
  end
end
