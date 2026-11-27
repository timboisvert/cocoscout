# frozen_string_literal: true

# The daily pass over contractors' requests about contract dates
# (ContractDateRequests.sweep!): closes the ones the calendar has passed by
# or the contract has since answered, and reminds the organization once
# about a request nobody has answered in three days. A request to connect a
# contract gets the same one reminder (ContractConnections.sweep!). Then
# other organizations' copies of contract dates catch up with any change a
# date's own hook couldn't pass on (LinkedDates.sweep!).
class ContractDateRequestsSweepJob < ApplicationJob
  queue_as :background

  def perform(now: Time.current)
    ContractDateRequests.sweep!(now: now)
    ContractConnections.sweep!(now: now)
    LinkedDates.sweep!
    # A date change someone started and never confirmed (Cancel or move this
    # date) is only its draft; a week old, it goes.
    DateChange.drafts.where(updated_at: ...7.days.ago).delete_all
    # ...and the followers shared through connected contracts are brought up to date.
    SharedFollowersSyncJob.perform_later
  end
end
