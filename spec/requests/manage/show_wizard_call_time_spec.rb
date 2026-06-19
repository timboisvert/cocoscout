# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Show wizard — cast call time", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }

  # The wizard persists step state in Rails.cache, which is the null-store in
  # tests — give it a real in-memory store so the multi-step flow carries over.
  let(:wizard_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(wizard_cache)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def walk_wizard(schedule_params)
    post manage_shows_wizard_save_event_type_path(production), params: { event_type: "show" }
    post manage_shows_wizard_save_schedule_path(production),
         params: { event_frequency: "single", duration_minutes: "120" }.merge(schedule_params)
    post manage_shows_wizard_save_location_path(production), params: { is_online: "false", location_id: location.id }
    post manage_shows_wizard_save_details_path(production), params: { secondary_name: "" }
    post manage_shows_wizard_create_path(production)
  end

  let(:start) { 1.week.from_now.change(hour: 19, min: 0, sec: 0) }

  it "sets a call time 1 hour before the event when enabled (default offset)" do
    expect {
      walk_wizard(date_and_time: start.strftime("%Y-%m-%dT%H:%M"), call_time_enabled: "1", call_time_offset_minutes: "60")
    }.to change(production.shows, :count).by(1)

    show = production.shows.order(:created_at).last
    expect(show.call_time_enabled).to be(true)
    expect(show.call_time).to be_within(1.minute).of(start - 60.minutes)
  end

  it "honors a chosen offset" do
    walk_wizard(date_and_time: start.strftime("%Y-%m-%dT%H:%M"), call_time_enabled: "1", call_time_offset_minutes: "90")
    show = production.shows.order(:created_at).last
    expect(show.call_time).to be_within(1.minute).of(start - 90.minutes)
  end

  it "leaves the call time off by default (toggle not enabled)" do
    walk_wizard(date_and_time: start.strftime("%Y-%m-%dT%H:%M"))
    show = production.shows.order(:created_at).last
    expect(show.call_time_enabled).to be(false)
    expect(show.call_time).to be_nil
  end

  it "applies the call time offset to every recurring event" do
    walk_wizard(
      event_frequency: "recurring",
      recurrence_start_datetime: start.strftime("%Y-%m-%dT%H:%M"),
      recurrence_pattern: "weekly",
      recurrence_end_type: "3_months",
      call_time_enabled: "1",
      call_time_offset_minutes: "60"
    )
    shows = production.shows.where.not(recurrence_group_id: nil)
    expect(shows.count).to be > 1
    shows.each do |s|
      expect(s.call_time_enabled).to be(true)
      expect(s.call_time).to be_within(1.minute).of(s.date_and_time - 60.minutes)
    end
  end
end
