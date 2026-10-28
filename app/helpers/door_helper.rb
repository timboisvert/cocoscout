# frozen_string_literal: true

module DoorHelper
  # When a show's door opens (DoorTonight.window), for "The door opens …":
  # "today at 6:00 PM", "tomorrow morning", "Fri Oct 24 at 6:00 PM".
  def door_opens_words(listing)
    opens = DoorTonight.window(listing.show, listing.organization.ticketing_profile).begin
    day = case opens.to_date
    when Date.current then "today"
    when Date.current + 1 then "tomorrow"
    else opens.strftime("%a %b %-d")
    end
    return "#{day} at #{opens.strftime('%-l:%M %p')}" unless opens == opens.beginning_of_day

    day == "tomorrow" ? "tomorrow morning" : "the morning of #{day}"
  end
end
