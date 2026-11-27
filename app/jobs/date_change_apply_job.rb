# frozen_string_literal: true

# Does a confirmed date change (ShowChangePlan::Apply), off the request, so
# a run of dates with many buyers to refund never times out, and the
# change's page shows each step finishing as it happens.
class DateChangeApplyJob < ApplicationJob
  queue_as :default

  def perform(change_id, user_id = nil)
    change = DateChange.find_by(id: change_id)
    return unless change && change.status == "applying"

    user = User.find_by(id: user_id) || change.created_by_user
    TimeZones.use(change.organization.time_zone.presence || TimeZones.default) do
      ShowChangePlan::Apply.call(change, by: user)
    end
  end
end
