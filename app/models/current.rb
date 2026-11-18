# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :session, :organization, :production
  # Shows changed in this request share one batch (ShowChanges), so a series
  # canceled at once is one thing to tell people about.
  attribute :show_change_batch
  # When the current day closes (DayClose), worked out once a request.
  attribute :day_closes
  delegate :user, to: :session, allow_nil: true
end
