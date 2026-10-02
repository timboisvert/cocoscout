# frozen_string_literal: true

# One Ticketing notice that must only go once (TicketingNotifier, once: true):
# what kind, what it was about, and for which occasion (a date, say).
class TicketingNotificationLog < ApplicationRecord
  belongs_to :organization
end
