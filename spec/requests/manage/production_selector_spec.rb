# frozen_string_literal: true

require "rails_helper"

# The searchable production picker on wizard "which production?" steps, and the
# cross-device recently-used list behind it (users.recent_production_ids).
RSpec.describe "Production selector", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:productions) do
    ("A".."G").map { |letter| create(:production, organization: org, name: "Production #{letter}") }
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "offers search and recents, keeping the full list behind a button" do
    owner.update!(recent_production_ids: [ productions[3].id, productions[0].id ])

    get manage_shows_new_wizard_path

    expect(response.body).to include("Search productions")
    expect(response.body).to include("Recently used")
    expect(response.body).to include("Show all 7 productions")
    # Recent rows render before the (collapsed) full list.
    expect(response.body.index("Recently used")).to be < response.body.index("All productions")
    # The full list starts hidden — the whole point is not facing the wall.
    expect(response.body).to match(/style="display: none" data-production-selector-target="allList"/)
  end

  it "hides the recents section when there's nothing recent, but still collapses the list" do
    get manage_shows_new_wizard_path
    expect(response.body).not_to include("Recently used")
    expect(response.body).to include("Show all 7 productions")
  end

  it "records the production on production-scoped page views" do
    get manage_shows_wizard_path(productions[2])
    expect(owner.reload.recent_production_ids.first).to eq(productions[2].id)

    get manage_shows_wizard_path(productions[5])
    expect(owner.reload.recent_production_ids.first(2)).to eq([ productions[5].id, productions[2].id ])
  end

  describe User, "#touch_recent_production" do
    it "moves repeats to the front instead of duplicating, and caps the list" do
      user = create(:user)
      (1..10).each { |id| user.touch_recent_production(id) }
      user.touch_recent_production(4)

      ids = user.reload.recent_production_ids
      expect(ids.first).to eq(4)
      expect(ids.size).to eq(User::RECENT_PRODUCTIONS_LIMIT)
      expect(ids.uniq.size).to eq(ids.size)
    end

    it "skips the write when the production is already first" do
      user = create(:user)
      user.touch_recent_production(7)
      expect(user).not_to receive(:update_column)
      user.touch_recent_production(7)
    end
  end
end
