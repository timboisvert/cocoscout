# frozen_string_literal: true

# Someone joined a mailing list that is shared through a contract, or a
# contract was connected: the Pro organizations the list is shared with get
# them as their own followers (SharedFollowers.sync!). With no list, every
# shared list is brought up to date (the daily pass).
class SharedFollowersSyncJob < ApplicationJob
  queue_as :background

  def perform(list_id = nil, organization_id: nil)
    if organization_id
      SharedFollowers.sync!(Organization.find_by(id: organization_id))
    elsif list_id
      SharedFollowers.sync_list!(MailingList.find_by(id: list_id))
    else
      MailingList.active.where(shared_with_contractor: true, source_list_id: nil).where.not(contractor_id: nil)
                 .find_each { |list| SharedFollowers.sync_list!(list) }
    end
  end
end
