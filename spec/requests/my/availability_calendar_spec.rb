# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Availability calendar", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:organization) { create(:organization, :pro) }
  let(:production) { create(:production, organization: organization) }
  let(:pool) { create(:talent_pool, production: production) }

  before do
    TalentPoolMembership.create!(talent_pool: pool, member: person)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "renders read-only day tiles with a status chip and an editable day modal using the standard rows" do
    show = create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 19, min: 30))
    create(:show_availability, :available, show: show, available_entity: person)
    unanswered = create(:show, production: production, date_and_time: 12.days.from_now)

    get my_availability_calendar_path
    expect(response).to have_http_status(:ok)

    # Desktop tiles: status chips, no inline thumbs buttons
    expect(response.body).to include("Available")
    expect(response.body).to include("Needs response")
    expect(response.body).not_to include("M6.633 10.25") # old thumb SVG path

    # Day cells open modals; the modal holds the standard availability row
    expect(response.body).to include("day-modal-#{show.date_and_time.to_date.iso8601}")
    expect(response.body).to include("day-modal-#{unanswered.date_and_time.to_date.iso8601}")
    expect(response.body).to include("availability#setStatus")
    expect(response.body).to include("request-item-#{show.id}-person_#{person.id}")
  end
end
