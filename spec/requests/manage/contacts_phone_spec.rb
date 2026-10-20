# frozen_string_literal: true

require "rails_helper"

# Contacts on a phone (V1.1 plan §4): the directory opens on a list of
# contact rows, and a person's page has the ways to reach them in a row.
RSpec.describe "Contacts on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:person) { create(:person, name: "Dana Scully", email: "dana@example.com", phone: "312-555-0142").tap { |p| org.people << p } }
  let(:iphone) { "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1" }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "opens the directory on contact rows on a phone, with Call, Text and Email" do
    get manage_contacts_path(filter: "everyone"), headers: { "User-Agent" => iphone }
    row = Nokogiri::HTML(response.body).css("[data-contact-row]").find { |r| r.text.include?("Dana Scully") }
    expect(row).to be_present
    hrefs = row.css("a").map { |a| a["href"] }
    expect(hrefs).to include("tel:3125550142", "sms:3125550142", "mailto:dana@example.com")
  end

  it "keeps tiles as the desktop's first view" do
    get manage_contacts_path(filter: "everyone")
    expect(response.body).not_to include("data-contact-row")
  end

  it "makes the phone a call link and puts Call, Text, Email and Message in a row on a person's page" do
    get manage_person_path(person)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("a[href='tel:3125550142']").size).to be >= 2
    actions = doc.at_css("[data-contact-actions]")
    expect(actions["class"]).to include("sm:hidden")
    expect(actions.text.squish).to include("Call", "Text", "Email", "Message")
  end
end
