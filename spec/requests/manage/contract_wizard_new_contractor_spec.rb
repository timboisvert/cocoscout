# frozen_string_literal: true

require "rails_helper"

# Creating a contractor from inside the New Contract wizard used to ask a
# shorter set of questions than the real New Contractor page — no way to say
# who the contractor is on CocoScout. Both now render the same fields.
RSpec.describe "Manage::ContractWizard new contractor", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  describe "the create-a-contractor modal" do
    it "asks who they are on CocoScout, the same as the New Contractor page" do
      get manage_new_contract_wizard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CocoScout user")
                           .and include("Search CocoScout by name or email")
                           .and include("Can't find them? Invite by email")
      # The fields that carry the choice through to the controller.
      expect(response.body).to include('name="person_id"')
                           .and include('name="invite_name"')
                           .and include('name="invite_email"')
    end

    it "offers the same secondary details the full page does" do
      get manage_new_contract_wizard_path

      expect(response.body).to include("More details (optional)")
                           .and include("contractor[phone]")
                           .and include("contractor[address]")
                           .and include("contractor[notes]")
    end

    it "renders the picker even when the org has no contractors yet" do
      expect(org.contractors).to be_empty

      get manage_new_contract_wizard_path

      expect(response.body).to include("No contractors yet").and include("CocoScout user")
    end
  end

  # The modal posts its form over fetch and stays put, so the JSON path has to
  # do the linking too — not just the HTML redirect path.
  describe "creating over JSON, the way the modal posts" do
    it "links an existing CocoScout person" do
      person = create(:person, name: "Sam Sound", email: "sam@example.com")
      org.people << person

      post manage_contractors_path,
           params: { contractor: { name: "Sound Co" }, person_id: person.id },
           as: :json

      expect(response).to have_http_status(:created)
      expect(org.contractors.find(response.parsed_body["id"]).person).to eq(person)
    end

    it "links a brand-new person by email without auto-inviting them" do
      expect {
        post manage_contractors_path,
             params: { contractor: { name: "Fresh Co" }, invite_name: "Newton Bell", invite_email: "fresh@example.com" },
             as: :json
      }.not_to change(PersonInvitation, :count)

      contractor = org.contractors.find(response.parsed_body["id"])
      expect(contractor.person.email).to eq("fresh@example.com")
      expect(contractor.person.user).to be_nil
    end

    it "still creates a contractor when nobody is chosen" do
      post manage_contractors_path, params: { contractor: { name: "Solo Co" } }, as: :json

      expect(response).to have_http_status(:created)
      expect(org.contractors.find(response.parsed_body["id"]).person).to be_nil
    end

    it "carries the secondary details through" do
      post manage_contractors_path,
           params: { contractor: { name: "Detailed Co", phone: "(555) 123-4567", notes: "Books early" } },
           as: :json

      contractor = org.contractors.find(response.parsed_body["id"])
      expect(contractor.phone).to eq("(555) 123-4567")
      expect(contractor.notes).to eq("Books early")
    end
  end
end
