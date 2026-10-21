# frozen_string_literal: true

require "rails_helper"

# My Shows & Events mixes shows with rehearsals and meetings, so each row
# wears the same event-type pill as Manage → Shows & Events.
RSpec.describe "My::Shows event type pill", type: :request do
  let(:password) { "Password123!" }
  let!(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user) }
  let!(:production) { create(:production, name: "Group Chat") }

  before do
    role = create(:role, production: production, name: "Producer")
    %w[show rehearsal].each_with_index do |type, i|
      show = create(:show, production: production, date_and_time: (i + 1).weeks.from_now, event_type: type, casting_finalized_at: Time.current)
      create(:show_person_role_assignment, show: show, assignable: person, role: role)
    end
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "labels each row with its event type" do
    get my_shows_path

    pills = Nokogiri::HTML(response.body).css("span.text-\\[10px\\]").map { |s| s.text.strip }
    expect(pills).to include(EventTypes.labels["show"] || "Show", EventTypes.labels["rehearsal"] || "Rehearsal")
  end
end
