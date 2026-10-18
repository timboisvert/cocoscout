# frozen_string_literal: true

require "rails_helper"

# A contract's date says one time everywhere (Tim, 2026-10-18): the show's
# own date_and_time is what the manage pages, the calendar and the ticket
# page all read. Editing it in Shows & Events keeps the booking's event
# time in step, and can't leave the slot the contract booked.
RSpec.describe Show, "on a contract's booking" do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, production_type: "third_party") }
  let(:day) { 2.weeks.from_now.to_date }
  let(:contract) { create(:contract, :active, organization: org, production: production) }
  let(:rental) do
    create(:space_rental, contract: contract, confirmed: true,
                          starts_at: day.in_time_zone.change(hour: 19, min: 30), ends_at: day.in_time_zone.change(hour: 22, min: 30),
                          event_starts_at: day.in_time_zone.change(hour: 20), event_ends_at: day.in_time_zone.change(hour: 22))
  end
  let(:show) { create(:show, production: production, space_rental: rental, location: rental.location, date_and_time: rental.effective_event_starts_at, duration_minutes: nil) }

  it "reads its own time, not the booking's, so every page agrees" do
    expect(show.time_range_display).to eq("8:00 PM – 10:00 PM")
    expect(show.ends_at).to eq(day.in_time_zone.change(hour: 22))

    show.update_columns(date_and_time: day.in_time_zone.change(hour: 19, min: 30)) # drifted, as show 1521 had
    expect(show.reload.time_range_display).to eq("7:30 PM – 9:30 PM")
  end

  it "moves the booking's event time with a hand edit inside the slot" do
    show.update!(date_and_time: day.in_time_zone.change(hour: 20, min: 30))
    rental.reload
    expect(rental.event_starts_at).to eq(day.in_time_zone.change(hour: 20, min: 30))
    expect(rental.event_ends_at).to eq(day.in_time_zone.change(hour: 22, min: 30))
    expect(rental.starts_at).to eq(day.in_time_zone.change(hour: 19, min: 30)) # the booked slot itself is the contract's
    expect(show.time_range_display).to eq("8:30 PM – 10:30 PM")
  end

  it "refuses a hand edit outside the booked slot and says where to change it" do
    expect(show.update(date_and_time: day.in_time_zone.change(hour: 23))).to be(false)
    expect(show.errors[:date_and_time].first).to include("outside the 7:30 PM to 10:30 PM the contract booked", "Change time on the contract")
    expect(rental.reload.event_starts_at).to eq(day.in_time_zone.change(hour: 20))
  end

  it "leaves the booking alone when it holds several shows" do
    show
    create(:show, production: production, space_rental: rental, location: rental.location, date_and_time: day.in_time_zone.change(hour: 21))
    show.update!(date_and_time: day.in_time_zone.change(hour: 19, min: 45))
    expect(rental.reload.event_starts_at).to eq(day.in_time_zone.change(hour: 20))
  end
end
