# frozen_string_literal: true

require "rails_helper"

# The shared People Picker's search (V1.1 plan §5): the organization's own
# people with their email, people outside it by name, profile key or exact
# email with no email shown, who's already added, availability for a show,
# and an invitation for an email nobody has.
RSpec.describe "Manage::PeoplePicker", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:abby) { create(:person, name: "Avail Abby", email: "abby@example.com", user: create(:user)).tap { |p| org.people << p } }
  let!(:ned) { create(:person, name: "Ned Nouser", email: "ned@example.com").tap { |p| org.people << p } }
  let!(:outsider) { create(:person, name: "Outside Olive", email: "olive@elsewhere.com", user: create(:user)) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def search(params)
    get manage_people_picker_search_path(params), headers: { "X-Requested-With" => "XMLHttpRequest" }
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def picks(doc)
    doc.css("[data-people-picker-row]").to_h { |row| [ row["data-people-picker-row"], JSON.parse(row["data-pick"]) ] }
  end

  it "asks for two characters, then finds the organization's people with their email" do
    expect(search(q: "a").text).to include("Type a name to find someone")
    doc = search(q: "abb")
    expect(doc.text).to include("In your organization")
    pick = picks(doc)["Person_#{abby.id}"]
    expect(pick).to include("type" => "Person", "id" => abby.id, "name" => "Avail Abby", "email" => "abby@example.com", "userId" => abby.user_id, "outside" => false)
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}']")["data-action"]).to eq("click->people-picker#pick")
  end

  it "finds people outside the organization by name without showing their email, and never by part of one" do
    doc = search(q: "olive", outside: "1")
    expect(doc.text).to include("On CocoScout, not in your organization")
    pick = picks(doc)["Person_#{outsider.id}"]
    expect(pick).to include("outside" => true, "email" => nil)
    expect(doc.text).not_to include("olive@elsewhere.com")
    expect(picks(search(q: "elsewhere", outside: "1"))).to be_empty
    expect(picks(search(q: "olive"))).to be_empty # not asked for
  end

  it "keeps the users scope to people with an account, marking the production's team" do
    ProductionPermission.create!(user: abby.user, production: production, role: "viewer")
    doc = search(q: "ne", scope: "users", production_id: production.id)
    expect(picks(doc)).not_to have_key("Person_#{ned.id}")
    doc = search(q: "ab", scope: "users", production_id: production.id)
    rows = picks(doc)
    expect(rows).to have_key("Person_#{abby.id}")
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}']")["disabled"]).to be_present
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}'] [data-people-picker-taken]").text).to eq("On the team")
  end

  it "marks the pool's members, badges the talent pool and availability, and takes an exclude list" do
    create(:talent_pool_membership, talent_pool: production.talent_pool, member: abby)
    doc = search(q: "ab", talent_pool_id: production.talent_pool.id, scope: "members")
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}'] [data-people-picker-taken]").text).to eq("In the pool")

    show = create(:show, production: production, date_and_time: 1.week.from_now)
    ShowAvailability.create!(show: show, available_entity: ned, status: :unavailable)
    doc = search(q: "ab", production_id: production.id, show_id: show.id)
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}']").text).to include("In the talent pool")
    doc = search(q: "ned", production_id: production.id, show_id: show.id)
    expect(doc.at_css("[data-people-picker-row='Person_#{ned.id}']").text).to include("Unavailable")

    doc = search(q: "ned", exclude: [ ned.id ])
    expect(doc.at_css("[data-people-picker-row='Person_#{ned.id}'] [data-people-picker-taken]").text).to eq("Already added")
  end

  it "offers to invite an email nobody has, with a name box when asked" do
    doc = search(q: "new@example.com", invite: "1")
    expect(doc.at_css("[data-people-picker-invite] button")["data-email"]).to eq("new@example.com")
    expect(doc.at_css("[data-people-picker-target='inviteName']")).to be_nil
    expect(search(q: "new@example.com", invite: "1", invite_name: "1").at_css("[data-people-picker-target='inviteName']")).to be_present
    expect(search(q: "abby@example.com", invite: "1").at_css("[data-people-picker-invite]")).to be_nil
  end

  it "is for managers" do
    viewer = create(:user, password: password)
    create(:organization_role, user: viewer, organization: org, company_role: "viewer")
    post handle_signin_path, params: { email_address: viewer.email_address, password: password }
    get manage_people_picker_search_path(q: "abb")
    expect(response).to redirect_to(manage_path)
  end
end
