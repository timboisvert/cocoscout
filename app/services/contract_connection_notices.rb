# frozen_string_literal: true

# Who is notified about a contract's connection to the contractor's own
# organization, and in what words (ContractConnectionTemplates).
# Notifications only, never an email. The organization that wrote the
# contract is reached through the people it chose for contract notices; the
# contractor's side through whoever made the request.
class ContractConnectionNotices
  ORGANIZATION_KINDS = %w[contract_connection_requested contract_connection_reminder].freeze

  class << self
    def requested(connection) = to_organization(connection, "contract_connection_requested", note: connection.note.to_s)
    def reminder(connection) = to_organization(connection, "contract_connection_reminder")
    # A later contract, connected under the yes they gave before.
    def connected_by_earlier_yes(connection) = to_organization(connection, "contract_connection_connected_by_earlier_yes")
    def accepted(connection) = to_contractor(connection, "contract_connection_accepted")
    def declined(connection) = to_contractor(connection, "contract_connection_declined", note: connection.answer_note.to_s)

    # The contractor chose where the contract's payments are sent: the organization that
    # pays it is notified, not asked.
    def pay_to_changed(connection)
      to_organization(connection, connection.pay_into_balance ? "contract_connection_pay_to_balance" : "contract_connection_pay_to_bank")
    end

    # A run paid a share into the contractor's organization's balance: the
    # people who run that organization are notified.
    def share_paid_into_balance(item)
      target = item.payee
      payer = item.payout_batch.organization
      amount = ActiveSupport::NumberHelper.number_to_currency(item.amount_cents / 100.0)
      path = routes.manage_connections_path
      User.where(id: [ target.owner_id ] + target.organization_roles.where(company_role: "manager").pluck(:user_id)).find_each do |user|
        Notifier.deliver(user: user, category: "contracts", kind: "contract_share_paid_into_balance",
                         template_key: "contract_share_paid_into_balance", path: path, organization: target, subject: item,
                         variables: { organization_name: payer.name, linked_organization_name: target.name, amount: amount,
                                      linked_organization_possessive: possessive(target.name), contractor_possessive: "",
                                      contractor_name: "", production_name: "", linked_production_name: "", note: "", connections_url: path })
      end
    rescue StandardError => e
      Rails.logger.error("[ContractConnectionNotices] item #{item.id} paid into balance: #{e.class}: #{e.message}")
      nil
    end

    # To the contractor, before any connection exists: that the contract
    # can be connected (once, when it first becomes true), and the same
    # pointed out by the organization that wrote it.
    def offer(contract, user, organizations)
      about_contract(contract, user, "contract_connection_offer",
                     linked_organization_name: organizations.one? ? organizations.first.name : "your own organization")
    end

    def told(contract, user) = about_contract(contract, user, "contract_connection_told")

    # Whoever ended it isn't notified of their own doing.
    def unlinked(connection, by_contractor_side:)
      if by_contractor_side
        to_organization(connection, "contract_connection_unlinked_by_contractor")
      else
        to_contractor(connection, "contract_connection_unlinked_by_organization")
      end
    end

    # A request taken back: the organization's notifications about it that
    # nobody has opened are removed, so nobody is sent to a request that
    # isn't there.
    def retract(connection)
      Notification.where(subject: connection, kind: ORGANIZATION_KINDS, read_at: nil).delete_all
    end

    private

    def to_organization(connection, key, extra = {})
      path = routes.manage_contract_path(connection.contract)
      connection.organization.contract_notification_recipients.filter_map(&:user).uniq.each do |user|
        deliver(user, connection, key, path, extra.merge(contract_url: path))
      end
    end

    def to_contractor(connection, key, extra = {})
      path = routes.my_contracts_path
      deliver(connection.requested_by, connection, key, path, extra.merge(contracts_url: path))
    end

    def deliver(user, connection, key, path, variables)
      contract = connection.contract
      Notifier.deliver(user: user, category: "contracts", kind: key, template_key: key, path: path,
                       organization: connection.organization, subject: connection,
                       variables: { contractor_name: contract.contractor_name, organization_name: connection.organization.name,
                                    linked_organization_name: connection.linked_organization.name,
                                    linked_organization_possessive: possessive(connection.linked_organization.name),
                                    contractor_possessive: possessive(contract.contractor_name),
                                    production_name: contract.production&.name || contract.production_name.to_s,
                                    linked_production_name: connection.production_name.to_s, note: "" }.merge(variables))
    rescue StandardError => e
      # A notice that can't be sent never undoes the request or the answer.
      Rails.logger.error("[ContractConnectionNotices] connection #{connection.id} #{key}: #{e.class}: #{e.message}")
      nil
    end

    def about_contract(contract, user, key, extra = {})
      path = routes.my_connect_contract_path(contract)
      Notifier.deliver(user: user, category: "contracts", kind: key, template_key: key, path: path,
                       organization: contract.organization, subject: contract,
                       variables: { contractor_name: contract.contractor_name, organization_name: contract.organization.name,
                                    linked_organization_name: "", linked_production_name: "", note: "", connect_url: path,
                                    production_name: contract.production&.name || contract.production_name.to_s }.merge(extra))
    rescue StandardError => e
      Rails.logger.error("[ContractConnectionNotices] contract #{contract.id} #{key}: #{e.class}: #{e.message}")
      nil
    end

    # "Rising Stars'" / "Thea's".
    def possessive(name) = name.to_s.end_with?("s") ? "#{name}'" : "#{name}'s"

    def routes = Rails.application.routes.url_helpers
  end
end
