# frozen_string_literal: true

# An organization's W-9 request to someone it pays who isn't on its staff,
# sent by PerformerW9SweepJob once they've been paid PerformerW9Requester::
# REQUEST_AT_CENTS in a year, with weekly reminders until the W-9 is in.
class W9Request < ApplicationRecord
  belongs_to :organization
  belongs_to :person

  def last_sent_at = last_reminded_at || requested_at
end
