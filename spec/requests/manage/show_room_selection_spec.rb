# frozen_string_literal: true

require "rails_helper"

# Shows can carry a location_space (room). Without one, the contract
# duplicate-checker treats the show as holding the entire venue, so it
# collides with every room. These specs cover picking a room in the show
# wizard and on the edit form, plus the model guard that drops a room
# belonging to a different location.
RSpec.describe "Show room selection", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:main_stage) { LocationSpace.create!(location: location, name: "Main Stage") }
  let!(:rouge_room) { LocationSpace.create!(location: location, name: "Rouge Room") }

  let(:wizard_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(wizard_cache)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  describe "show wizard" do
    it "offers the location's spaces on the location step" do
      post manage_shows_wizard_save_event_type_path(production), params: { event_type: "show" }
      post manage_shows_wizard_save_schedule_path(production), params: {
        event_frequency: "single", date_and_time: "2027-06-04T20:00"
      }

      get manage_shows_wizard_location_path(production)

      expect(response.body).to include("Main Stage")
      expect(response.body).to include("Entire venue")
    end

    it "creates the show with the chosen room" do
      post manage_shows_wizard_save_event_type_path(production), params: { event_type: "show" }
      post manage_shows_wizard_save_schedule_path(production), params: {
        event_frequency: "single", date_and_time: "2027-06-04T20:00"
      }
      post manage_shows_wizard_save_location_path(production), params: {
        is_online: "false", location_id: location.id, location_space_id: rouge_room.id
      }
      post manage_shows_wizard_save_details_path(production), params: { secondary_name: "" }
      post manage_shows_wizard_create_path(production)

      show = production.shows.last
      expect(show.location).to eq(location)
      expect(show.location_space).to eq(rouge_room)
    end

    it "carries the room onto every show in a recurring series" do
      post manage_shows_wizard_save_event_type_path(production), params: { event_type: "show" }
      post manage_shows_wizard_save_schedule_path(production), params: {
        event_frequency: "recurring",
        recurrence_start_datetime: "2027-06-04T20:00",
        recurrence_pattern: "weekly",
        recurrence_end_date: "2027-09-04"
      }
      post manage_shows_wizard_save_location_path(production), params: {
        is_online: "false", location_id: location.id, location_space_id: main_stage.id
      }
      post manage_shows_wizard_save_details_path(production), params: { secondary_name: "" }
      post manage_shows_wizard_create_path(production)

      shows = production.shows.to_a
      expect(shows.size).to be > 1
      expect(shows.map(&:location_space_id).uniq).to eq([ main_stage.id ])
    end
  end

  describe "edit form" do
    let!(:show) do
      production.shows.create!(event_type: "show", date_and_time: 2.weeks.from_now, location: location)
    end

    it "renders the space select with the location's rooms" do
      get edit_manage_production_show_path(production, show)

      expect(response.body).to include("Main Stage")
      expect(response.body).to include("Entire venue")
    end

    it "saves the chosen room" do
      patch manage_production_show_path(production, show), params: {
        show: { event_type: "show", date_and_time: show.date_and_time,
                location_id: location.id, location_space_id: main_stage.id }
      }

      expect(show.reload.location_space).to eq(main_stage)
    end

    it "clears the room when the show switches to a location that doesn't have it" do
      show.update!(location_space: main_stage)
      other_location = create(:location, organization: org)

      patch manage_production_show_path(production, show), params: {
        show: { event_type: "show", date_and_time: show.date_and_time,
                location_id: other_location.id, location_space_id: main_stage.id }
      }

      expect(show.reload.location).to eq(other_location)
      expect(show.reload.location_space).to be_nil
    end

    it "clears the room when the show goes online" do
      show.update!(location_space: main_stage)

      patch manage_production_show_path(production, show), params: {
        show: { event_type: "show", date_and_time: show.date_and_time,
                is_online: "true", online_location_info: "zoom.example" }
      }

      expect(show.reload.is_online).to be(true)
      expect(show.reload.location_space).to be_nil
    end
  end
end
