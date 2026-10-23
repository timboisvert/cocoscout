# frozen_string_literal: true

module Manage
  # Who can see a list in My Followers, through the standard search-or-invite
  # (the shared People Picker, as Ticketing's "Who sees sales" uses it):
  # someone the organization knows or anyone on CocoScout found by name or
  # exact email (create), or an email nobody has yet (invite). They get an
  # email saying so; someone new gets the account-setup invitation first.
  class MailingListSharesController < ManageController
    before_action :set_list

    def create
      person = shareable_people.where(id: params[:person_id]).first
      return redirect_to(manage_mailing_list_path(@list), alert: "Pick someone to share it with.") unless person

      share!(person)
      redirect_to manage_mailing_list_path(@list), notice: "#{person.name} can see #{@list.name} in their My Followers."
    end

    # An email typed into the picker that no one on CocoScout has: a contact
    # and a login for them, the share, and the standard account-setup
    # invitation (cocoscout-invite-pattern).
    def invite
      email = params[:email].to_s.strip.downcase
      return redirect_to(manage_mailing_list_path(@list), alert: "Enter an email address to invite.") unless email.match?(URI::MailTo::EMAIL_REGEXP)

      user = User.find_by(email_address: email)
      person = user&.person || Person.where("LOWER(email) = ?", email).order(Arel.sql("user_id IS NULL")).first
      person ||= Person.create!(name: params[:name].to_s.squish.presence || email.split("@").first, email: email)
      Current.organization.people << person unless Current.organization.people.exists?(person.id)
      new_account = ensure_login_for(person)

      share!(person, notify: !new_account)
      if new_account
        invitation = PersonInvitation.pending.find_by(email: person.email, organization: Current.organization) ||
                     PersonInvitation.create!(email: person.email, organization: Current.organization)
        Manage::PersonMailer.person_invitation(invitation).deliver_later
        redirect_to manage_mailing_list_path(@list), notice: "Invitation sent to #{email}. Once they set up their account, #{@list.name} is in their My Followers."
      else
        redirect_to manage_mailing_list_path(@list), notice: "#{person.name} can see #{@list.name} in their My Followers."
      end
    end

    def destroy
      share = @list.mailing_list_shares.find(params[:share_id])
      share.destroy!
      redirect_to manage_mailing_list_path(@list), notice: "#{share.person.name} can't see #{@list.name} anymore."
    end

    private

    def share!(person, notify: true)
      share = @list.mailing_list_shares.find_or_initialize_by(person: person)
      return unless share.new_record?

      share.granted_by = Current.user
      share.save!
      FollowerNoticeMailer.share_invitation(share).deliver_later if notify && person.email.present?
    end

    # Someone the organization knows (its people, the producers and people on
    # its contracts), or anyone with a CocoScout account the picker found by
    # name or exact email. Sharing hands them this organization's own list, so
    # a platform-wide lookup is intended here.
    def shareable_people
      org = Current.organization
      contracts = Contract.where(organization: org)
      Person.where(id: org.people.select(:id))
            .or(Person.where(id: ContractPerson.where(contract_id: contracts.select(:id)).select(:person_id)))
            .or(Person.where(id: Contractor.where(organization: org).where.not(person_id: nil).select(:person_id)))
            .or(Person.where.not(user_id: nil))
    end

    # A login for someone new (a random password; the invitation sets it).
    # True when one was made or never used, so they get the setup invitation.
    def ensure_login_for(person)
      if person.user.blank?
        user = User.find_by(email_address: person.email.downcase) ||
               User.create!(email_address: person.email.downcase, password: User.generate_secure_password)
        person.update!(user: user)
      end
      person.user.last_seen_at.blank?
    end

    def set_list
      @list = Current.organization.mailing_lists.find(params[:id])
    end
  end
end
