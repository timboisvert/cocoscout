# frozen_string_literal: true

# A check-in taken back at the door (TicketDoor#uncheck): who did it, and the
# check-in it took back. The ticket's order shows them.
class TicketUncheck < ApplicationRecord
  belongs_to :ticket
  belongs_to :ticket_listing
  belongs_to :unchecked_by, class_name: "User", optional: true
  belongs_to :checked_in_by, class_name: "User", optional: true
end
