# frozen_string_literal: true

# One message thread per contract (linked productions step 5; Tim,
# 2026-11-22): the organization's owner and managers, the contractor, the
# people on the contract, and the managers of the contractor's connected
# organization, all in it, each in their own inbox. It's an ordinary Message
# thread that regards the contract, so the inbox, replies, unread counts and
# the digest work as they do everywhere; everyone on the contract is
# subscribed each time someone writes, so people added later join it.
class ContractThread
  def self.root(contract)
    Message.root_messages.not_deleted
           .joins(:message_regards).where(message_regards: { regardable_type: "Contract", regardable_id: contract.id })
           .order(:created_at).first
  end

  # Everyone in it, as sign-ins.
  def self.participants(contract)
    users = manager_users(contract.organization)
    users << ContractConnections.contractor_user(contract)
    users.concat(contract.contract_people.includes(person: :user).filter_map { |cp| cp.person&.user })
    linked = contract.connections.connected.first&.linked_organization
    users.concat(manager_users(linked)) if linked
    users.compact.uniq
  end

  def self.can_post?(user, contract)
    user.present? && participants(contract).include?(user)
  end

  # Writes into the thread, starting it if it isn't there yet. Returns the
  # thread's first message.
  def self.post!(contract, sender:, body:)
    root = root(contract)
    recipients = (participants(contract) - [ sender ]).filter_map(&:person)
    message = MessageService.create_message(
      sender: sender, recipients: recipients, body: body, message_type: :direct, visibility: :personal,
      subject: root ? "Re: #{root.subject}" : "About the contract for #{contract.display_name}",
      organization: contract.organization, production: contract.production, parent_message: root
    )
    raise ArgumentError, "Nobody else on this contract has a CocoScout account yet." unless message

    message.add_regards(contract) unless root
    # Anyone added since it started joins it.
    participants(contract).each { |user| message.root_message.subscribe!(user, mark_read: user == sender) }
    message.root_message
  end

  def self.manager_users(organization)
    return [] unless organization

    ids = organization.organization_roles.where(company_role: "manager").pluck(:user_id)
    ids << organization.owner_id
    User.where(id: ids.compact.uniq).includes(:default_person).to_a
  end
end
