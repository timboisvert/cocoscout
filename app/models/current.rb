# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :session, :organization, :production
  # Shows changed in this request share one batch (ShowChanges), so a series
  # canceled at once is one thing to tell people about.
  attribute :show_change_batch
  # The dates a change is taking off together (ShowChangePlan::Apply): while
  # they go one by one, the ones still to go already count as off, so a
  # shift covering two of them is seen as off with the last, not kept.
  attribute :show_change_off_ids
  # When the current day closes (DayClose), worked out once a request.
  attribute :day_closes
  delegate :user, to: :session, allow_nil: true
end
