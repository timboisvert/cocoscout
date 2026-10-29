# frozen_string_literal: true

require "rails_helper"

# Messaging a production (Tim, 2026-10-29). A performer's Messages has a
# Message a production button: one production opens the contact window, more
# open a sheet of them first, each saying why they can write to it. (The old
# box's Send Message did nothing on this page: the window was never on it.)
# A producer's Send a message offers People, A show and A production, which
# reaches everyone cast in its upcoming shows, its talent pool, or both, and
# is sent as that production.
RSpec.describe "Messaging a production", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:owner_person) { create(:person, user: owner, name: "Veronica Producer").tap { |p| owner.update!(default_person: p) } }
  let(:late) { create(:production, organization: org, name: "Late Night Laughs") }
  let(:brunch) { create(:production, organization: org, name: "Burlesque Brunch") }
  let(:performer) { create(:user, password: password) }
  let!(:emmanuel) { create(:person, user: performer, name: "Emmanuel Okoye").tap { |p| performer.update!(default_person: p); org.people << p } }

  def sign_in(user) = post(handle_signin_path, params: { email_address: user.email_address, password: password })

  def cast(person, production, at:)
    role = production.roles.first || create(:role, production: production, name: "Ensemble")
    show = create(:show, production: production, date_and_time: at)
    ShowPersonRoleAssignment.create!(show: show, role: role, assignable: person, position: 0)
    show
  end

  describe "a performer" do
    it "gets Message a production, a sheet of their productions with why, and the window that sends it" do
      cast(emmanuel, late, at: Time.zone.local(2026, 11, 6, 20))
      cast(emmanuel, brunch, at: 3.days.ago)
      sign_in(performer)

      travel_to Time.zone.local(2026, 10, 29, 12) do
        get messages_path
      end
      doc = Nokogiri::HTML(response.body)
      header = doc.at_css("[data-module-header]")
      button = header.css("a, button").find { |el| el.text.squish == "Message a production" }
      expect(button["data-modal-id"]).to eq("message-a-production")

      rows = doc.css("[data-message-a-production] button").map { |row| row.text.squish }
      expect(rows).to include(a_string_including("Late Night Laughs", "Stars & Garters", "You're cast Fri, Nov 6"),
                              a_string_including("Burlesque Brunch", "You've been cast in its shows"))
      expect(doc.at_css("[data-message-a-production] button")["data-action"]).to eq("click->modal#close click->contact-production#open")
      expect(doc.at_css("[data-contact-production-target='modal']")).to be_present
      expect(response.body).not_to include("Need to reach a production team?")
    end

    it "opens the window straight away when there's one production" do
      cast(emmanuel, late, at: 2.days.from_now)
      sign_in(performer)
      get messages_path
      doc = Nokogiri::HTML(response.body)
      button = doc.at_css("[data-module-header]").css("a, button").find { |el| el.text.squish == "Message a production" }
      expect(button["data-action"]).to eq("click->contact-production#open")
      expect(button["data-production-id"]).to eq(late.id.to_s)
      expect(doc.at_css("[data-contact-production-target='modal']")).to be_present
    end

    it "shows no button to someone with no production to write to" do
      sign_in(performer)
      get messages_path
      expect(response.body).not_to include("Message a production")
    end
  end

  describe "a producer in production mode" do
    before do
      sign_in(owner)
      get manage_path
    end

    it "offers People, A show and A production" do
      get messages_path
      cards = Nokogiri::HTML(response.body).css("[data-compose-message-target='recipientCards'] [data-value]")
      expect(cards.map { |c| c["data-value"] }).to eq(%w[individuals show_cast production])
      expect(cards.map { |c| c.at_css("p").text.squish }).to eq([ "People", "A show", "A production" ])
    end

    it "gives the window a production's upcoming cast and its talent pool as lists" do
      coming = create(:person, name: "Coming Up")
      gone = create(:person, name: "Long Gone")
      [ coming, gone ].each { |p| org.people << p }
      cast(coming, late, at: 2.days.from_now)
      cast(gone, late, at: 10.days.ago)
      pool_member = create(:person, name: "In The Pool")
      org.people << pool_member
      pool = late.effective_talent_pool || TalentPool.create!(production: late, name: "Late Night Laughs Talent Pool")
      TalentPoolMembership.create!(talent_pool: pool, member: pool_member)

      get production_data_manage_messages_path(late.id), headers: { "Accept" => "application/json" }
      audience = JSON.parse(response.body)["audience"]
      expect(audience["name"]).to eq("Late Night Laughs")
      expect(audience["cast_ids"]).to eq([ coming.id ])
      expect(audience["pool_ids"]).to include(pool_member.id)
      expect(audience["faces"].map { |f| f["name"] }).to include("Coming Up", "In The Pool")
    end

    it "sends a production's whole list as that production" do
      a = create(:person, name: "Avery Patel", user: create(:user))
      b = create(:person, name: "Sam Okafor", user: create(:user))
      [ a, b ].each { |p| org.people << p }
      expect {
        post manage_messages_path, params: { recipient_type: "batch", person_ids: [ a.id, b.id ], production_id: late.id,
                                             subject: "Call times", body: "<p>Friday at 6:30</p>", sender_identity: "production_team" }
      }.to change(Message, :count).by(1)
      expect(Message.last.production).to eq(late)
      expect(Message.last.message_recipients.pluck(:recipient_id)).to contain_exactly(a.id, b.id)
    end
  end
end
