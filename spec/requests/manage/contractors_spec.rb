# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Contractors", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:contractor) { org.contractors.create!(name: "Sound Co") }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  # Explicitly link a Person to the contractor (the new deliberate flow).
  def link!(**attrs)
    person = create(:person, **attrs)
    org.people << person
    contractor.update!(person: person)
    person
  end

  describe "associated person" do
    it "shows the search-or-invite picker when no person is linked" do
      get manage_contractor_path(contractor)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Associated person").and include("Link a person")
    end

    it "links an existing CocoScout person via the picker" do
      person = create(:person, name: "Sam Sound", email: "sam@example.com")
      org.people << person
      expect { post link_person_manage_contractor_path(contractor), params: { person_id: person.id } }
        .to change { contractor.reload.person }.from(nil).to(person)
      expect(response).to redirect_to(manage_contractor_path(contractor))
    end

    it "invites a brand-new person by email and links them (with a login + invitation)" do
      expect {
        post link_person_manage_contractor_path(contractor), params: { invite_name: "New Person", invite_email: "new@example.com" }
      }.to change(PersonInvitation, :count).by(1)
      person = contractor.reload.person
      expect(person.email).to eq("new@example.com")
      expect(person.user).to be_present
    end
  end

  describe "creating with an associated person" do
    it "links an existing person chosen on the create form" do
      person = create(:person, name: "Ann Artist", email: "ann@example.com")
      org.people << person
      post manage_contractors_path, params: { contractor: { name: "Ann's Co" }, person_id: person.id }
      created = org.contractors.find_by(name: "Ann's Co")
      expect(created.person).to eq(person)
    end

    it "invites a new person entered on the create form" do
      expect {
        post manage_contractors_path, params: { contractor: { name: "Fresh Co" }, invite_name: "Newton Bell", invite_email: "fresh@example.com" }
      }.to change(PersonInvitation, :count).by(1)
      created = org.contractors.find_by(name: "Fresh Co")
      expect(created.person.email).to eq("fresh@example.com")
      expect(created.person.user).to be_present
    end

    it "creates a contractor with no person when none is chosen" do
      post manage_contractors_path, params: { contractor: { name: "Solo Co" } }
      expect(org.contractors.find_by(name: "Solo Co").person).to be_nil
    end

    it "surfaces an invite validation failure instead of silently dropping it" do
      # A genuinely malicious name is rejected; the contractor still saves.
      post manage_contractors_path, params: { contractor: { name: "Trip Co" }, invite_name: "cat /etc/passwd", invite_email: "josh@example.com" }
      expect(org.contractors.find_by(name: "Trip Co").person).to be_nil
      follow_redirect!
      expect(response.body).to include("couldn&#39;t link a person").or include("couldn't link a person")
    end
  end

  describe "the person-picker search (link mode)" do
    let!(:member) { create(:person, name: "Existing Member", email: "member@example.com").tap { |p| org.people << p } }

    it "renders an existing org member as selectable in link mode" do
      get search_for_invite_manage_people_path(q: "Existing", mode: "link")
      expect(response.body).to include("invite-search#selectPerson").and include("Existing Member")
      expect(response.body).not_to include("Already a member")
    end

    it "keeps org members non-selectable without link mode" do
      get search_for_invite_manage_people_path(q: "Existing")
      expect(response.body).to include("Already a member")
    end
  end

  describe "getting paid" do
    it "offers a bank-onboarding link once a person is linked but not bank-connected" do
      link!(email: "sound@example.com")
      get manage_contractor_path(contractor)
      expect(response.body).to include("Bank setup link").and include("/pay/setup/")
    end

    it "shows the connected state once the linked person can receive payouts" do
      link!(email: "sound@example.com", stripe_account_id: "acct_x", payouts_enabled: true)
      get manage_contractor_path(contractor)
      expect(response.body).to include("Bank connected")
    end
  end

  describe "CocoScout access" do
    it "invites the linked person" do
      link!(email: "sound@example.com")
      expect { post invite_manage_contractor_path(contractor) }.to change(PersonInvitation, :count).by(1)
      expect(contractor.reload.person.user).to be_present
    end

    it "errors when no person is linked yet" do
      post invite_manage_contractor_path(contractor)
      expect(response).to redirect_to(manage_contractor_path(contractor))
      follow_redirect!
      expect(response.body).to include("Link a person")
    end
  end
end
