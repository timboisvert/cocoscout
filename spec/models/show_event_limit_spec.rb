# frozen_string_literal: true

require "rails_helper"

RSpec.describe Show, "free-plan event limit validation", type: :model do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:base) { Time.zone.now.beginning_of_month + 10.days }

  def fill_month_to_limit
    Organization::FREE_MONTHLY_EVENT_LIMIT.times { |i| create(:show, production: production, date_and_time: base + i.hours) }
  end

  it "blocks creating an event beyond the monthly limit for a free org" do
    fill_month_to_limit
    extra = build(:show, production: production, date_and_time: base + 100.hours)

    expect(extra).not_to be_valid
    expect(extra.errors[:base].join).to match(/free plan limit/i)
  end

  it "still allows a canceled event at the limit" do
    fill_month_to_limit
    canceled = build(:show, production: production, date_and_time: base + 100.hours, canceled: true)
    expect(canceled).to be_valid
  end

  it "allows unlimited events for a paid org" do
    organization.update!(comped_indefinitely: true)
    fill_month_to_limit
    extra = build(:show, production: production, date_and_time: base + 100.hours)
    expect(extra).to be_valid
  end

  it "does not block events in a different (under-limit) month" do
    fill_month_to_limit
    next_month = build(:show, production: production, date_and_time: base + 1.month)
    expect(next_month).to be_valid
  end
end
