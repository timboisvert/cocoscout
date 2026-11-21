# frozen_string_literal: true

# Connecting a contract to the contractor's own organization
# (ContractConnection): the request, the answer, and ending it. The
# contractor requests; the organization that wrote the contract accepts or
# declines; either side can unlink. The dates themselves are LinkedDates'.
class ContractConnections
  class NotAllowed < StandardError; end

  # The organizations a user runs: the ones they own, and the ones they
  # manage.
  def self.managed_organization_ids(user)
    return [] unless user

    Organization.where(owner_id: user.id).pluck(:id) | OrganizationRole.where(user_id: user.id, company_role: "manager").pluck(:organization_id)
  end

  # Where this contractor could connect the contract: an organization they
  # run, other than the one the contract is with.
  def self.organizations_for(user, contract)
    Organization.where(id: managed_organization_ids(user)).where.not(id: contract.organization_id).order(:name)
  end

  def self.contractor?(user, contract)
    user.present? && contract.present? && contract.payee_among?(user.people.pluck(:id))
  end

  # Anyone on the contract: the contractor, and the people added to it
  # (ContractPerson). They all see what the contract shares (Tim,
  # 2026-11-17: "not just the contract holder but anyone on the contract
  # team"): its dates, ticket sales, what it pays and its followers. Only
  # the contractor signs, connects and unlinks.
  def self.on_contract?(user, contract)
    user.present? && contract.present? && Contract.visible_to(user).exists?(id: contract.id)
  end

  # Only the contractor requests, on a live contract with nothing live on it
  # already, and only when they run an organization of their own. A fact
  # about them and the contract: nothing is guessed from names.
  def self.can_request?(user, contract)
    contractor?(user, contract) && contract.status_active? && contract.connections.live.none? &&
      organizations_for(user, contract).exists?
  end

  # The contractor's sign-in, when they have one: the user behind the person
  # the contract pays.
  def self.contractor_user(contract)
    contract&.contractor&.person&.user
  end

  # Whether there's still something to connect: a date on the contract that
  # hasn't happened. Nobody is offered a connection for a run that's over.
  def self.dates_ahead?(contract)
    LinkedDates.contract_shows(contract).where(canceled: false).where("shows.date_and_time > ?", Time.current).exists?
  end

  # The offer, made once per contract: the contractor is notified that the
  # contract can be connected, as soon as that's a fact (they run an
  # organization of their own, the contract is live with dates ahead, and
  # nothing connects it yet). Called when a contract goes live, and when
  # someone comes to run an organization (offer_all_for). Never guessed
  # from names, and never repeated: after this it's a row on My Contracts.
  def self.offer!(contract)
    user = contractor_user(contract)
    return false unless user && contract.connect_offered_at.nil? && contract.connections.none?
    return false unless can_request?(user, contract) && dates_ahead?(contract)

    contract.update_columns(connect_offered_at: Time.current)
    ContractConnectionNotices.offer(contract, user, organizations_for(user, contract).to_a)
    true
  end

  # Someone has just come to run an organization: every live contract of
  # theirs that could now be connected is offered.
  def self.offer_all_for(user)
    return unless user

    Contract.where(status: "active", connect_offered_at: nil)
            .joins(:contractor).where(contractors: { person_id: user.people.select(:id) })
            .find_each { |contract| offer!(contract) }
  end

  # "Not now": the offer leaves My Contracts and the organization's home,
  # and stays as a quiet link on the contract. It never comes back by itself.
  def self.not_now!(contract, user:)
    raise NotAllowed unless contractor?(user, contract)

    contract.update_columns(connect_offer_dismissed_at: Time.current) if contract.connect_offer_dismissed_at.nil?
    contract
  end

  # The contracts a user is offered to connect to this organization of
  # theirs: live, with dates ahead, nothing live on them, the offer not put
  # away. For the line on the organization's home. `put_away: true` keeps
  # the ones they said "Not now" to, for the one place that asks in passing
  # (starting a new production).
  def self.offers_for(user, organization, put_away: false)
    return [] unless user && organization && managed_organization_ids(user).include?(organization.id)

    scope = Contract.where(status: "active").where.not(organization_id: organization.id)
    scope = scope.where(connect_offer_dismissed_at: nil) unless put_away
    scope.joins(:contractor).where(contractors: { person_id: user.people.select(:id) })
            .where.not(id: ContractConnection.live.select(:contract_id))
            .includes(:organization, :production).select { |contract| dates_ahead?(contract) }
  end

  # The organization that wrote the contract points the contractor at it
  # ("Tell <contractor>"): once per contract, to a contractor who can sign
  # in. It says nothing about whether they run an organization: the page it
  # opens does, to them alone.
  def self.can_tell?(contract)
    contract.status_active? && contract.connect_told_at.nil? && contract.connections.none? &&
      contractor_user(contract).present? && dates_ahead?(contract)
  end

  def self.tell!(contract, user:)
    return false unless can_tell?(contract)

    contract.update_columns(connect_told_at: Time.current, connect_told_by_id: user&.id)
    ContractConnectionNotices.told(contract, contractor_user(contract))
    true
  end

  # The request. `production` is one of theirs; without one,
  # `new_production_name` is made into a production when it's accepted.
  # `date_answers` is what they said about dates already there (LinkedDates).
  def self.request!(contract:, user:, organization:, production: nil, new_production_name: nil, note: nil, date_answers: {})
    raise NotAllowed unless can_request?(user, contract)
    raise NotAllowed unless organizations_for(user, contract).exists?(id: organization.id)

    standing = standing_yes(contract, organization: organization)
    connection = contract.connections.create!(
      organization: contract.organization, linked_organization: organization, linked_production: production,
      new_production_name: (new_production_name.to_s.strip.presence unless production), requested_by: user,
      note: note.to_s.strip.presence, date_answers: date_answers || {}, **sales_defaults(organization)
    )
    if standing
      # They already said yes to this: it connects now, and they're notified.
      accept!(connection, user: standing.answered_by, later_contracts: standing.later_contracts, standing: true)
    else
      ContractConnectionNotices.requested(connection)
    end
    connection
  end

  # The yes the organization already gave for a later contract: a contract
  # of the same contractor's that it connected to this same organization of
  # theirs, choosing then to connect later ones too: every later contract,
  # or the ones for the same production of its own. Its choice as it stands
  # today (it can change it on that contract's page); a connection since
  # unlinked carries nothing.
  def self.standing_yes(contract, organization:)
    return nil unless contract && organization

    ContractConnection.connected.where(organization_id: contract.organization_id, linked_organization_id: organization.id)
                      .where.not(contract_id: contract.id).where.not(later_contracts: "ask")
                      .joins(:contract).where(contracts: { contractor_id: contract.contractor_id })
                      .includes(:contract).order(answered_at: :desc)
                      .detect do |earlier|
      earlier.later_contracts == "all" ||
        (contract.production_id.present? && earlier.contract.production_id == contract.production_id)
    end
  end

  # The contractor takes an unanswered request back.
  def self.withdraw!(connection, user:)
    raise NotAllowed unless theirs?(connection, user)
    return connection unless connection.requested?

    connection.update!(status: "withdrawn", ended_by: user, ended_at: Time.current)
    ContractConnectionNotices.retract(connection)
    connection
  end

  # The organization's yes. The production is made now if they asked for a
  # new one, and the contract's dates go into it.
  # `standing`: it connects under a yes they gave earlier (standing_yes), so
  # nobody answered just now: the organization is notified, not the
  # contractor who has just done it.
  def self.accept!(connection, user:, later_contracts: "ask", standing: false)
    return connection unless connection.requested?

    ContractConnection.transaction do
      production = connection.linked_production || LinkedDates.create_production!(connection)
      connection.update!(status: "connected", linked_production: production, answered_by: user, answered_at: Time.current)
      # Under an earlier yes it takes that choice as it is; an answer given
      # now is the organization's latest word for this contractor.
      standing ? connection.update!(later_contracts: later_contracts) : choose_later_contracts!(connection, later_contracts)
      LinkedDates.connect!(connection)
    end
    standing ? ContractConnectionNotices.connected_by_earlier_yes(connection) : ContractConnectionNotices.accepted(connection)
    # A list shared through this contract now belongs in their organization.
    SharedFollowersSyncJob.perform_later(organization_id: connection.linked_organization_id)
    connection
  end

  # The organization's choice for later contracts with this contractor. It
  # is one answer, whichever contract's page it's given on, so the other
  # contracts already connected to the same organization of theirs are
  # brought into line: "ask" and "every later contract" hold for all of
  # them, and "this production" narrows any that said every one.
  def self.choose_later_contracts!(connection, choice)
    choice = choice.to_s.presence_in(ContractConnection::LATER_CONTRACTS) || "ask"
    connection.update!(later_contracts: choice)
    others = ContractConnection.connected.where(organization_id: connection.organization_id, linked_organization_id: connection.linked_organization_id)
                               .where.not(id: connection.id)
                               .where(contract_id: Contract.where(contractor_id: connection.contract.contractor_id).select(:id))
    others = others.where(later_contracts: "all") if choice == "production"
    others.where.not(later_contracts: choice).update_all(later_contracts: choice, updated_at: Time.current)
    connection
  end

  def self.decline!(connection, user:, note: nil)
    return connection unless connection.requested?

    connection.update!(status: "declined", answered_by: user, answered_at: Time.current, answer_note: note.to_s.strip.presence)
    ContractConnectionNotices.declined(connection)
    connection
  end

  # Either side ends it. Nothing already done is undone: the dates in the
  # contractor's production stay, as their own, and stop following.
  # `remove_coming`: the contractor's side also removes the coming dates
  # nobody is on (LinkedDates.remove_released!); otherwise every date stays.
  def self.unlink!(connection, user:, remove_coming: false)
    return connection unless connection.connected?

    by_contractor_side = theirs?(connection, user)
    ContractConnection.transaction do
      LinkedDates.release!(connection)
      connection.update!(status: "unlinked", ended_by: user, ended_at: Time.current)
      LinkedDates.remove_released!(connection) if remove_coming && by_contractor_side
    end
    ContractConnectionNotices.unlinked(connection, by_contractor_side: by_contractor_side)
    connection
  end

  # The daily pass: one reminder to the organization about a request nobody
  # has answered in three days.
  def self.sweep!(now: Time.current)
    ContractConnection.requested.where(reminded_at: nil).where("contract_connections.created_at < ?", now - ContractConnection::REMIND_AFTER)
                      .includes(:contract, :organization, :linked_organization).find_each do |connection|
      next unless connection.contract.status_active?

      connection.update!(reminded_at: now)
      ContractConnectionNotices.reminder(connection)
    rescue StandardError => e
      Rails.logger.error("[ContractConnections] connection #{connection.id}: #{e.class}: #{e.message}")
    end
  end

  # ---- Where the share is paid (Tim, 2026-11-17) ------------------------
  #
  # A connected contract's share can be paid into the contractor's own
  # organization's CocoScout balance, in place of the contractor's bank. The
  # contractor chooses, per connection: it is the contractor's pay. The
  # organization that wrote the contract is notified, not asked. It applies
  # to payments not yet on a payout run; anything already on one goes where
  # it was going.

  # A balance comes with Pro: only an organization on Pro can be paid into.
  def self.balance_available?(organization)
    organization.present? && organization.feature_available?(:money) && CocoScoutBalance.pooled?(organization)
  end

  # The organization whose balance this contract's share is paid into right
  # now, or nil for the contractor's bank: connected, chosen, and still on
  # Pro. If Pro lapses or the connection ends, the next payment goes to the
  # contractor's bank again, with nothing to switch back.
  def self.pay_target(contract)
    connection = contract && contract.connections.connected.where(pay_into_balance: true).includes(:linked_organization).first
    target = connection&.linked_organization
    target if target && balance_available?(target)
  end

  # The contractor's choice. Only the contractor makes it.
  def self.set_pay_to!(connection, user:, balance:)
    raise NotAllowed unless connection.connected? && contractor?(user, connection.contract)
    raise NotAllowed if balance && !balance_available?(connection.linked_organization)
    return connection if connection.pay_into_balance == balance

    connection.update!(pay_into_balance: balance, pay_choice_by: user, pay_choice_at: Time.current)
    ContractConnectionNotices.pay_to_changed(connection)
    connection
  end

  # The contractor's side of a connection: whoever requested it, the
  # contractor themself, or anyone who runs the linked organization.
  def self.theirs?(connection, user)
    return false unless user

    connection.requested_by_id == user.id || contractor?(user, connection.contract) ||
      managed_organization_ids(user).include?(connection.linked_organization_id)
  end

  # Who in their organization sees the sales starts from what its own box
  # office chose, when it has one.
  def self.sales_defaults(organization)
    profile = TicketingProfile.find_by(organization_id: organization.id)
    return {} unless profile

    { team_manager_sales: profile.team_manager_sales, team_viewer_sales: profile.team_viewer_sales, cast_sales: profile.cast_sales }
      .select { |key, value| value.in?(ContractConnection.const_get(key.to_s.upcase)) }
  end
  private_class_method :sales_defaults
end
