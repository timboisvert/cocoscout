# frozen_string_literal: true

module Manage
  # Who can see a list in My Followers: add someone (the shared people
  # picker; they get an email saying so) or take them off.
  class MailingListSharesController < ManageController
    before_action :set_list

    def create
      person = shareable_people.find_by(id: params[:person_id])
      return redirect_to(manage_mailing_list_path(@list), alert: "Pick someone to share it with.") unless person

      share = @list.mailing_list_shares.find_or_initialize_by(person: person)
      if share.new_record?
        share.granted_by = Current.user
        share.save!
        FollowerNoticeMailer.share_invitation(share).deliver_later if person.email.present?
      end
      redirect_to manage_mailing_list_path(@list), notice: "#{person.name} can see #{@list.name} in their My Followers."
    end

    def destroy
      share = @list.mailing_list_shares.find(params[:share_id])
      share.destroy!
      redirect_to manage_mailing_list_path(@list), notice: "#{share.person.name} can't see #{@list.name} anymore."
    end

    private

    # Someone the organization knows: its people, and the producers and
    # people on its contracts.
    def shareable_people
      org = Current.organization
      contracts = Contract.where(organization: org)
      Person.where(id: org.people.select(:id))
            .or(Person.where(id: ContractPerson.where(contract_id: contracts.select(:id)).select(:person_id)))
            .or(Person.where(id: Contractor.where(organization: org).where.not(person_id: nil).select(:person_id)))
    end

    def set_list
      @list = Current.organization.mailing_lists.find(params[:id])
    end
  end
end
