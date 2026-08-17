# frozen_string_literal: true

require "rails_helper"

# An act-based lineup can repeat a name ("Magic" in each half of the show).
# Switching a show between the production's lineup and its own copy must map
# each occurrence to its own counterpart, not lump them together by name.
RSpec.describe "Manage::ShowRoles lineup migration by ordinal", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, casting_mode: "act_based") }
  let(:show) { create(:show, production: production) }
  let!(:magic1) { create(:role, production: production, name: "Magic", position: 0) }
  let!(:clown) { create(:role, production: production, name: "Clown", position: 1) }
  let!(:magic2) { create(:role, production: production, name: "Magic", position: 2) }
  let(:opener) { create(:person) }
  let(:closer) { create(:person) }

  before do
    create(:show_person_role_assignment, show: show, role: magic1, assignable: opener)
    create(:show_person_role_assignment, show: show, role: magic2, assignable: closer)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "previews each Magic mapping onto its own copy when switching to a custom lineup" do
    get manage_migration_preview_show_roles_path(production, show, switching_to: "custom")

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["needs_decision_count"]).to eq(0)
    expect(body["auto_mappable_count"]).to eq(2)
    # Both suggested targets exist and are distinct (production roles here since nothing is copied yet)
    targets = body["mappings"].map { |m| m["suggested_target_role_id"] }
    expect(targets.uniq.size).to eq(2)
  end

  it "moves the opener to the first Magic copy and the closer to the second" do
    post manage_execute_migration_show_roles_path(production, show),
         params: { switching_to: "custom", role_mappings: [] }, as: :json

    expect(response).to have_http_status(:ok)
    show.reload
    expect(show).to be_use_custom_roles
    copies = show.custom_roles.to_a
    expect(copies.map(&:name)).to eq(%w[Magic Clown Magic])

    first_copy, _clown_copy, second_copy = copies
    expect(show.show_person_role_assignments.find_by(assignable: opener).role).to eq(first_copy)
    expect(show.show_person_role_assignments.find_by(assignable: closer).role).to eq(second_copy)
  end
end
