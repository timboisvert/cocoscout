# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Course offering: invite instructor", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let!(:production) { create(:production, organization: org, production_type: :course) }
  let!(:offering) { create(:course_offering, production: production) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def invite(name:, email:)
    post manage_course_offering_invite_instructor_path(offering),
         params: { name: name, email: email }, as: :json
  end

  it "creates a person with an account, adds them to the org, and sends an invitation" do
    expect {
      invite(name: "New Teacher", email: "Teacher@Example.com")
    }.to change(Person, :count).by(1)
      .and change(User, :count).by(1)
      .and change(PersonInvitation, :count).by(1)
      .and have_enqueued_job(ActionMailer::MailDeliveryJob)

    person = Person.find_by(email: "teacher@example.com")
    expect(person).to be_present
    expect(person.user).to be_present
    expect(person.organizations).to include(org)

    invitation = PersonInvitation.last
    expect(invitation.email).to eq("teacher@example.com")
    expect(invitation.organization).to eq(org)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["success"]).to be(true)
    expect(body["person_id"]).to eq(person.id)
  end

  it "reuses an existing person by email and adds them to the org without a new invitation" do
    existing = create(:person, email: "existing@example.com")

    expect {
      invite(name: "Existing Person", email: "existing@example.com")
    }.to change(Person, :count).by(0)
      .and change(User, :count).by(0)
      .and change(PersonInvitation, :count).by(0)

    expect(existing.organizations.reload).to include(org)

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["success"]).to be(true)
    expect(body["person_id"]).to eq(existing.id)
  end

  it "rejects a blank name or email" do
    invite(name: "", email: "someone@example.com")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["success"]).to be(false)

    invite(name: "Someone", email: "")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["success"]).to be(false)
  end

  it "returns a validation error when a user account already exists for the email" do
    create(:user, email_address: "taken@example.com")

    expect {
      invite(name: "Colliding Person", email: "taken@example.com")
    }.not_to change(PersonInvitation, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["success"]).to be(false)
  end
end
