# frozen_string_literal: true

require "rails_helper"

# Member-side isolation: a signed-in user must not reach people or shows in
# organizations they have no relationship with.
RSpec.describe "Cross-org isolation (member side)", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }

  let!(:stranger_org) { create(:organization) }
  let!(:stranger_production) { create(:production, organization: stranger_org) }
  let!(:stranger) do
    # Needs a user account — MessageService silently drops account-less recipients.
    create(:person, email: "stranger@example.com", user: create(:user)).tap { |p| stranger_org.people << p }
  end

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  describe "direct messages (M-8)" do
    it "refuses to DM a person with no shared org, course, or thread" do
      expect {
        post my_direct_messages_path, params: { person_id: stranger.id, subject: "Hi", body: "hello" }
      }.not_to change(Message, :count)
      expect(flash[:alert]).to eq("You can't message this person")
    end

    it "allows messaging someone in a shared organization" do
      shared_org = create(:organization)
      shared_org.people << person
      shared_org.people << stranger

      expect {
        post my_direct_messages_path, params: { person_id: stranger.id, subject: "Hi", body: "hello" }
      }.to change(Message, :count).by(1)
    end

    it "allows a student to message their course instructor (no shared org)" do
      production = create(:production, organization: stranger_org, production_type: "course")
      offering = create(:course_offering, production: production)
      offering.course_registrations.create!(person: person, status: :confirmed, amount_cents: 0,
                                            currency: "usd", registered_at: Time.current)
      CourseOfferingInstructor.create!(course_offering: offering, person: stranger)

      expect {
        post my_direct_messages_path, params: { person_id: stranger.id, subject: "Hi", body: "question" }
      }.to change(Message, :count).by(1)
    end
  end

  describe "availability writes (low)" do
    it "404s writing my availability against a show in an org I don't belong to" do
      show = create(:show, production: stranger_production)

      expect {
        patch my_update_availability_path(show), params: { entity_key: "person_#{person.id}", status: "available" }
      }.not_to change(ShowAvailability, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "still allows availability for shows in my own org" do
      my_org = create(:organization)
      my_org.people << person
      my_production = create(:production, organization: my_org)
      show = create(:show, production: my_production)

      patch my_update_availability_path(show), params: { entity_key: "person_#{person.id}", status: "available" }

      expect(response).to have_http_status(:ok)
      expect(ShowAvailability.find_by(available_entity: person, show: show).status).to eq("available")
    end
  end
end
