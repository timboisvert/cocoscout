# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::Documents", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:production) { create(:production) }
  let!(:document) do
    production.documents.create!(title: "Shared Handbook", body: "<div>Read me</div>").tap do |d|
      d.set_sharing!(team: { enabled: false }, talent_pools: {}, people: { person.id.to_s => "read" })
    end
  end

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "lists documents shared with the signed-in person and renders one" do
    get my_documents_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shared Handbook")
    expect(response.body).to include(production.name)

    get my_document_path(document)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Read me")
  end

  it "does not expose a document the person can't see" do
    hidden = production.documents.create!(title: "Internal Only", body: "<div>secret</div>")
    hidden.set_sharing!(team: { enabled: true, permission: "write" }, talent_pools: {}, people: {})

    get my_documents_path
    expect(response.body).not_to include("Internal Only")

    get my_document_path(hidden)
    expect(response).to redirect_to(my_documents_path)
  end

  # A producer is on the production team via their org role, so a team-shared
  # document they create in /manage must also surface in /my/documents.
  it "shows team-shared documents to a producer (org-level manager)" do
    org = create(:organization, owner: user)
    create(:organization_role, :manager, user: user, organization: org)
    producer_production = create(:production, organization: org)
    team_doc = producer_production.documents.create!(title: "Staff Onboarding", body: "<div>welcome</div>")
    team_doc.apply_default_sharing! # team + write, by default

    get my_documents_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Staff Onboarding")

    get my_document_path(team_doc)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("welcome")
  end
end
