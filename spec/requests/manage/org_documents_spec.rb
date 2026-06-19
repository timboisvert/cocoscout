# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::OrgDocuments", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "lists documents across the productions the user manages" do
    production.documents.create!(title: "Org Handbook", body: "<div>hi</div>").apply_default_sharing!

    get manage_org_documents_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Org Handbook")
    expect(response.body).to include(production.name)
  end

  it "renders the new form with a production picker" do
    get manage_new_org_document_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("production_id")
    expect(response.body).to include(production.name)
  end

  it "creates a document in the chosen production and redirects to its editor" do
    expect {
      post manage_org_documents_path, params: {
        production_ids: [ production.id ],
        production_document: { title: "Created From Hub" }
      }
    }.to change(ProductionDocument, :count).by(1)

    doc = ProductionDocument.last
    expect(doc.production).to eq(production)
    expect(doc.shared_with_team?).to be(true)
    expect(response).to redirect_to(edit_manage_production_document_path(production, doc))
  end

  it "creates one document that applies to several productions" do
    other = create(:production, organization: org, name: "Rising Stars")
    post manage_org_documents_path, params: {
      production_ids: [ production.id, other.id ],
      production_document: { title: "Performer Handbook" }
    }
    doc = ProductionDocument.last
    expect(doc.productions).to contain_exactly(production, other)
    expect(production.applied_documents).to include(doc)
    expect(other.applied_documents).to include(doc)
  end

  it "re-renders new when no production is chosen" do
    post manage_org_documents_path, params: { production_document: { title: "No Prod" } }
    expect(response).to redirect_to(manage_new_org_document_path)
  end
end
