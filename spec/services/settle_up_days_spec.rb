# frozen_string_literal: true

require "rails_helper"

# The Settle up list reads every day's registers and door cash at once
# (it was asking per day, 2026-11-02).
RSpec.describe SettleUp, ".days" do
  let(:org) { create(:organization, :pro) }

  def show_on(days_ago)
    listing = create(:ticket_listing, organization: org)
    listing.show.update!(date_and_time: days_ago.days.ago.change(hour: 19))
    listing
  end

  it "reads many days in the same handful of queries as one" do
    show_on(2)
    range = 30.days.ago.to_date..Date.current
    one = count_queries { described_class.days(org, range).each { |d| [ d.door_cash.expected_cents, d.registers.size, d.any? ] } }
    3.times { |i| show_on(4 + i) }
    four = count_queries { described_class.days(org, range).each { |d| [ d.door_cash.expected_cents, d.registers.size, d.any? ] } }
    expect(described_class.days(org, range).size).to eq(4)
    expect(four - one).to be <= 2
  end
end
