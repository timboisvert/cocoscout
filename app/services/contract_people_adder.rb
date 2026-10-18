# frozen_string_literal: true

# Puts someone on a contract (ContractPerson), the one way: from the wizard's
# "Who's on this contract" step when the contract is activated
# (Contract#apply_draft_people!), and from Amend → Change who's on it.
# Someone on CocoScout joins at once; someone without an account gets an
# emailed invitation that puts them on the contract when they accept
# (Manage::TeamInvitationsController#do_accept). Never a production
# permission: contract people live on My (docs/contract_people_plan.md).
class ContractPeopleAdder
  # outcome: :added, :invited, :already, :invited_already
  Result = Data.define(:outcome, :name, :invitation)

  def self.add!(contract, by: nil, person: nil, user: nil, email: nil, name: nil)
    email = email.to_s.strip.downcase.presence
    user ||= User.find_by(email_address: email) if email && person.nil?
    person ||= user.default_person || user.people.order(:created_at).first if user

    if person
      display = person.name.presence || name.to_s.squish.presence || "Someone"
      return Result.new(outcome: :already, name: display, invitation: nil) if contract.contractor&.person_id == person.id
      return Result.new(outcome: :already, name: display, invitation: nil) if contract.contract_people.exists?(person_id: person.id)

      if person.user_id.present?
        contract.contract_people.create!(person: person, added_by: by)
        return Result.new(outcome: :added, name: display, invitation: nil)
      end

      # A profile with no account (someone in the organization's contacts):
      # invited to make one, and the invitation carries their profile so
      # accepting links it and puts them on the contract.
      email = person.email.to_s.strip.downcase.presence
      name = display
    end

    raise ArgumentError, "an email address is needed to invite someone" unless email&.match?(URI::MailTo::EMAIL_REGEXP)

    existing = TeamInvitation.find_by(email: email, contract: contract, accepted_at: nil)
    return Result.new(outcome: :invited_already, name: name.to_s.squish.presence || email, invitation: existing) if existing

    invitation = TeamInvitation.create!(email: email, organization: contract.organization, contract: contract, person: person)
    Manage::TeamMailer.contract_invite(invitation, name: name.to_s.squish.presence).deliver_later
    Result.new(outcome: :invited, name: name.to_s.squish.presence || email, invitation: invitation)
  end
end
