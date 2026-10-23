# frozen_string_literal: true

# Before a show's door opens the door sells presale and checks nobody in
# (TicketListing#door_ahead?, Tim 2026-10-23). Specs about selling or
# checking in on the night, whose show is days out and whose clock doesn't
# matter, open every door with this. The door before it opens has its own
# examples (door_spec, ticket_door_spec, door_tonight_spec).
module DoorHelpers
  def open_every_door!
    allow_any_instance_of(TicketListing).to receive(:door_ahead?).and_return(false)
  end
end

RSpec.configure do |config|
  config.include DoorHelpers
end
