# frozen_string_literal: true

# A room's access guide (accessibility plan §4): the room's accessibility
# profile as plain sections, linked from the show page, the confirmation
# email and the PDF ticket. Reads the free profile; writes nothing.
class TicketAccessGuidesController < TicketsController
  def show
    @room = LocationSpace.joins(:location).where(locations: { organization_id: @organization.id }).find(params[:room])
    @location = @room.location
    @profile = AccessProfile.for(@room)
  end
end
