# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::Casting per-individual notify", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let!(:roles) { create_list(:role, 5, production: production) }
  let(:show) { create(:show, production: production) }

  # Cast 4 of the 5 roles (show stays NOT fully cast).
  let!(:cast) do
    roles.first(4).map do |role|
      person = create(:person)
      create(:show_person_role_assignment, show: show, role: role, assignable: person)
      person
    end
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def visible_keys
    show.show_person_role_assignments.visible_to_performers.pluck(:assignable_type, :assignable_id).to_set
  end

  describe "POST notify (partial, no finalize)" do
    it "notifies only the selected members and does not finalize the show" do
      expect(show.fully_cast?).to be(false)

      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: [ "Person:#{cast[0].id}", "Person:#{cast[1].id}" ],
        cast_email_draft: { title: "You're in!", body: "Congrats" }
      }
      expect(response).to redirect_to(manage_casting_show_cast_path(production, show))

      show.reload
      expect(show.casting_finalized?).to be(false)

      # Selected two are now visible to performers; the other two are not.
      expect(visible_keys).to include([ "Person", cast[0].id ], [ "Person", cast[1].id ])
      expect(visible_keys).not_to include([ "Person", cast[2].id ], [ "Person", cast[3].id ])

      # Exactly two cast notifications recorded.
      expect(show.show_cast_notifications.cast_notifications.count).to eq(2)
    end

    it "rejects when nothing is selected" do
      post manage_casting_show_notify_path(production, show), params: { assignable_keys: [] }
      expect(show.reload.show_cast_notifications).to be_empty
    end
  end

  describe "removing an already-notified person" do
    it "clears their notification (and hides them) when a removal notice is sent" do
      # Notify person 0, then remove them from the cast.
      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: [ "Person:#{cast[0].id}" ], cast_email_draft: { title: "Hi", body: "x" }
      }
      expect(show.show_cast_notifications.cast_notifications.where(assignable: cast[0]).count).to eq(1)

      show.show_person_role_assignments.find_by(assignable: cast[0]).destroy!

      post manage_casting_show_notify_path(production, show), params: {
        removed_keys: [ "Person:#{cast[0].id}" ], removed_email_draft: { title: "Update", body: "y" }
      }

      expect(show.show_cast_notifications.cast_notifications.where(assignable: cast[0])).to be_empty
    end
  end

  describe "POST finalize (whole show) still works once fully cast" do
    it "locks the show and notifies everyone" do
      # Fill the 5th role so the show is fully cast.
      create(:show_person_role_assignment, show: show, role: roles.last, assignable: create(:person))
      expect(show.reload.fully_cast?).to be(true)

      post manage_casting_show_finalize_path(production, show), params: {
        cast_email_draft: { title: "Cast!", body: "z" }
      }

      expect(show.reload.casting_finalized?).to be(true)
      # All five cast members are visible once finalized.
      expect(show.show_person_role_assignments.visible_to_performers.count).to eq(5)
    end
  end

  describe "auto-lock: notifying the last member finalizes the show" do
    let!(:fifth) { create(:person).tap { |p| create(:show_person_role_assignment, show: show, role: roles.last, assignable: p) } }

    it "does NOT lock while someone is still unnotified" do
      keys = (cast.first(4)).map { |p| "Person:#{p.id}" }
      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: keys, cast_email_draft: { title: "Hi", body: "x" }
      }
      expect(show.reload.casting_finalized?).to be(false) # fifth still unnotified
    end

    it "locks once the final member is notified" do
      all_keys = (cast + [ fifth ]).map { |p| "Person:#{p.id}" }
      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: all_keys, cast_email_draft: { title: "Hi", body: "x" }
      }
      expect(show.reload.casting_finalized?).to be(true)
    end

    it "ignores guests when deciding 'everyone notified'" do
      # Replace the 5th assignment with a guest; notifying the 4 people should lock.
      show.show_person_role_assignments.find_by(assignable: fifth).destroy!
      show.show_person_role_assignments.create!(role: roles.last, guest_name: "Guest Star")
      expect(show.reload.fully_cast?).to be(true)

      keys = cast.map { |p| "Person:#{p.id}" }
      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: keys, cast_email_draft: { title: "Hi", body: "x" }
      }
      expect(show.reload.casting_finalized?).to be(true)
    end
  end

  describe "message interpolation" do
    it "delivers a message with placeholders replaced (no literal {{...}})" do
      recipient = create(:user)
      person = create(:person, user: recipient)
      role = roles.first
      show.show_person_role_assignments.where(role: role).destroy_all
      create(:show_person_role_assignment, show: show, role: role, assignable: person)

      post manage_casting_show_notify_path(production, show), params: {
        assignable_keys: [ "Person:#{person.id}" ],
        cast_email_draft: { title: "Cast in {{production_name}}", body: "<div>Role: {{role_name}} for {{production_name}}</div>" }
      }

      msg = Message.order(:created_at).last
      expect(msg).to be_present
      expect(msg.subject).to include(production.name)
      expect(msg.subject).not_to include("{{")
      expect(msg.body.to_plain_text).to include(production.name)
      expect(msg.body.to_plain_text).not_to include("{{")
    end
  end
end
