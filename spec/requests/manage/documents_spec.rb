# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Documents", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "creates a document shared with the production team (write) by default" do
    expect {
      post manage_production_documents_path(production), params: {
        production_document: { title: "Performer Handbook", body: "<div>Welcome!</div>" }
      }
    }.to change(ProductionDocument, :count).by(1)

    doc = ProductionDocument.last
    expect(doc.body.to_plain_text).to include("Welcome!")
    expect(doc.shared_with_team?).to be(true)
    expect(doc.team_permission).to eq("write")
    expect(response).to redirect_to(edit_manage_production_document_path(production, doc))
  end

  it "updates sharing (audiences + read/write) via the share action" do
    doc = production.documents.create!(title: "X", body: "<div>x</div>")
    doc.apply_default_sharing!
    pool = production.talent_pool
    extra = create(:person, name: "Stan Stage")

    patch share_manage_production_document_path(production, doc), params: {
      team_enabled: "1", team_permission: "read",
      talent_pools: { pool.id.to_s => { enabled: "1", permission: "write" } },
      people: { extra.id.to_s => "read" }
    }

    doc.reload
    expect(doc.team_permission).to eq("read")
    expect(doc.pool_permission(pool.id)).to eq("write")
    expect(doc.person_share_ids).to include(extra.id)
  end

  it "lists, shows, edits, and deletes" do
    doc = production.documents.create!(title: "Rules", body: "<div>Be kind</div>")
    doc.apply_default_sharing!

    get manage_production_documents_path(production)
    expect(response.body).to include("Rules")

    get manage_production_document_path(production, doc)
    expect(response.body).to include("Be kind")
    expect(response.body).to include("sharing-modal-#{doc.id}") # share modal lives on the view page

    get edit_manage_production_document_path(production, doc)
    expect(response).to have_http_status(:ok)

    expect {
      delete manage_production_document_path(production, doc)
    }.to change(ProductionDocument, :count).by(-1)
  end

  describe "talent pool option in the sharing modal" do
    let!(:document) { production.documents.create!(title: "Handbook", body: "<div>x</div>").tap(&:apply_default_sharing!) }
    let(:member) { create(:person, name: "Pat Pool") }

    it "offers the production's own pool (named for the production) once it has members" do
      production.talent_pool.talent_pool_memberships.create!(member: member)
      get manage_production_document_path(production, document)
      expect(response.body).to include("#{production.name} Talent Pool")
    end

    it "hides the pool option when the production pool has no members" do
      get manage_production_document_path(production, document)
      expect(response.body).not_to include("Talent Pool")
    end

    it "offers the organization pool when the org runs a single shared pool" do
      org.find_or_create_talent_pool!
      org.update!(talent_pool_mode: :single)
      org.talent_pool.talent_pool_memberships.create!(member: member)
      get manage_production_document_path(production, document)
      expect(response.body).to include("#{org.name} Talent Pool")
    end

    it "offers a Shared Talent Pool (listing productions) when borrowing another pool" do
      other = create(:production, organization: org, name: "Mainstage")
      other.talent_pool.talent_pool_memberships.create!(member: member)
      TalentPoolShare.create!(production: production, talent_pool: other.talent_pool)

      get manage_production_document_path(production, document)
      expect(response.body).to include("Shared Talent Pool")
      expect(response.body).to include("Mainstage")
    end
  end

  it "renders the Documents tab on the production edit page" do
    production.documents.create!(title: "Onboarding Guide", body: "<div>hi</div>").apply_default_sharing!
    get edit_manage_production_path(production)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("All documents") # header button into the documents tab
    expect(response.body).to include("Onboarding Guide")
  end
end
