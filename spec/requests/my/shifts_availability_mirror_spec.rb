# frozen_string_literal: true

require "rails_helper"

# While the new time-band model is being proven, the existing My Shifts screen
# keeps writing the old table and every write is mirrored into the new one —
# so the two never disagree about what the person actually said.
RSpec.describe "My::Shifts availability mirrored into time bands", type: :request do
  let(:user) { create(:user, password: "Password123!") }
  let!(:person) { create(:person, user: user) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: "Password123!" } }

  it "mirrors marks as they're set" do
    post my_create_shift_unavailability_path, params: { dates: %w[2026-10-01 2026-10-02], scope: "evening" }, as: :json

    entries = person.staff_availability_entries.order(:starts_on)
    expect(entries.map { |e| e.starts_on.to_s }).to eq(%w[2026-10-01 2026-10-02])
    expect(entries.map { |e| [ e.starts_minute, e.ends_minute ] }.uniq).to eq([ [ 17 * 60, 1440 ] ])
    expect(entries.map(&:source).uniq).to eq([ "migrated" ])
  end

  it "mirrors marks being cleared" do
    post my_create_shift_unavailability_path, params: { dates: %w[2026-10-01], scope: "all_day" }, as: :json
    post my_create_shift_unavailability_path, params: { dates: %w[2026-10-01], scope: "clear" }, as: :json

    expect(person.staff_availability_entries).to be_empty
  end

  it "mirrors a switch to 'when I'm available' as never-unless-marked" do
    post my_set_shift_availability_mode_path, params: { mode: "available" }, as: :json

    expect(person.staff_availability_entries.weekly.unavailable.count).to eq(7)
  end
end
