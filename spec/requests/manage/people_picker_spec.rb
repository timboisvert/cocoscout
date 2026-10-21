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

# Casting's needs (V1.1 plan §5): the pool before a search, availability
# over a linked event's dates, who's in the show, a restricted role's
# approvals, and a guest by name.
RSpec.describe "Manage::PeoplePicker for casting", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, date_and_time: 1.week.from_now) }
  let!(:role) { create(:role, production: production, name: "Host") }
  let(:abby) { create(:person, name: "Avail Abby").tap { |p| org.people << p } }
  let(:ned) { create(:person, name: "Ned Nope").tap { |p| org.people << p } }
  let(:quinn) { create(:person, name: "Quiet Quinn").tap { |p| org.people << p } }
  let(:group) { create(:group, name: "The Ensemble") }

  before do
    [ abby, ned, quinn, group ].each { |m| create(:talent_pool_membership, talent_pool: production.talent_pool, member: m) }
    ShowAvailability.create!(show: show, available_entity: abby, status: :available)
    ShowAvailability.create!(show: show, available_entity: ned, status: :unavailable)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def search(params)
    get manage_people_picker_search_path(params), headers: { "X-Requested-With" => "XMLHttpRequest" }
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def keys(doc)
    doc.css("[data-people-picker-row]").map { |r| r["data-people-picker-row"] }
  end

  it "lists the talent pool before a search, available first, then no answer, then unavailable" do
    doc = search(list: "pool", scope: "members", production_id: production.id, show_id: show.id)
    expect(doc.text).to include("In the talent pool")
    expect(keys(doc)).to eq([ "Person_#{abby.id}", "Person_#{quinn.id}", "Person_#{ned.id}", "Group_#{group.id}" ])
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}']").text).to include("Available")
    expect(doc.at_css("[data-people-picker-row='Person_#{ned.id}']").text).to include("Unavailable")
  end

  it "says who's in the show already: not pickable, or a badge on an act-based night" do
    show.show_person_role_assignments.create!(role: show.available_roles.first, assignable: abby)
    doc = search(list: "pool", production_id: production.id, show_id: show.id)
    row = doc.at_css("[data-people-picker-row='Person_#{abby.id}']")
    expect(row["disabled"]).to be_present
    expect(row.at_css("[data-people-picker-taken]").text).to eq("Already in this show")

    doc = search(list: "pool", production_id: production.id, show_id: show.id, in_show: "badge")
    row = doc.at_css("[data-people-picker-row='Person_#{abby.id}']")
    expect(row["disabled"]).to be_nil
    expect(row.text).to include("Already in this show")
  end

  it "marks who a restricted role hasn't approved, and says so in the pick" do
    show_role = show.available_roles.first
    show_role.role_eligibilities.build(member: abby)
    show_role.update!(restricted: true)
    doc = search(list: "pool", production_id: production.id, show_id: show.id, role_id: show_role.id)
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}']").text).not_to include("Not approved")
    ned_row = doc.at_css("[data-people-picker-row='Person_#{ned.id}']")
    expect(ned_row.text).to include("Not approved for this role")
    expect(JSON.parse(ned_row["data-pick"])["eligible"]).to be(false)
    expect(JSON.parse(doc.at_css("[data-people-picker-row='Person_#{abby.id}']")["data-pick"])["eligible"]).to be(true)
  end

  it "counts a linked event's dates in the availability badge" do
    linked = create(:show, production: production, date_and_time: 8.days.from_now)
    linkage = EventLinkage.create!(production: production)
    [ show, linked ].each { |s| s.update!(event_linkage: linkage) }
    doc = search(list: "pool", production_id: production.id, show_id: show.id)
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}']").text).to include("Available 1 of 2 dates")
  end

  it "offers a guest by name when searching, with the invited and excluded marked" do
    doc = search(q: "zz", production_id: production.id, guest: "1")
    expect(doc.at_css("[data-people-picker-guest] [data-people-picker-target='guestName']")["value"]).to eq("zz")
    expect(doc.at_css("[data-people-picker-guest] button")["data-action"]).to eq("click->people-picker#guest")

    doc = search(list: "pool", scope: "members", production_id: production.id, invited: [ abby.id ], exclude: [ "Group_#{group.id}" ], exclude_label: "Can't make it")
    expect(doc.at_css("[data-people-picker-row='Person_#{abby.id}'] [data-people-picker-taken]").text).to eq("Already invited")
    expect(doc.at_css("[data-people-picker-row='Group_#{group.id}'] [data-people-picker-taken]").text).to eq("Can't make it")
  end
end

# Staffing's shift assign (V1.1 plan §5): everyone qualified for the role,
# free for all of it first, with what they said, who's on it, who's in a
# show that night and who's on an overlapping shift, and the fit filters.
RSpec.describe "Manage::PeoplePicker for a shift", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, name: "Late Show") }
  let(:tech) { create(:house_role, organization: org, name: "Tech") }
  let(:bar) { create(:house_role, organization: org, name: "Bar") }
  let(:friday) { Date.current.beginning_of_week + 1.week + 4 }
  let!(:shift) { create(:shift, organization: org, house_role: tech, starts_at: friday.in_time_zone.change(hour: 18), ends_at: friday.in_time_zone.change(hour: 22)) }

  def staff!(name)
    person = create(:person, name: name).tap { |p| org.people << p }
    member = create(:organization_staff_member, organization: org, person: person)
    create(:staff_role_qualification, organization_staff_member: member, house_role: tech)
    person
  end

  let!(:free) { staff!("Free Fran") }
  let!(:off) { staff!("Off Oli") }
  let!(:busy) { staff!("Busy Bea") }
  let!(:performing) { staff!("Performing Pat") }
  let!(:on_it) { staff!("Already Al") }
  let!(:barkeep) { create(:person, name: "Bar Bob").tap { |p| org.people << p; create(:staff_role_qualification, organization_staff_member: create(:organization_staff_member, organization: org, person: p), house_role: bar) } }

  before do
    StaffAvailabilityWriter.new(off).save_exception!(starts_on: friday, ends_on: friday, state: "off")
    other = create(:shift, organization: org, house_role: bar, starts_at: friday.in_time_zone.change(hour: 20), ends_at: friday.in_time_zone.change(hour: 23))
    other.shift_assignments.create!(person: busy)
    show = create(:show, production: production, date_and_time: friday.in_time_zone.change(hour: 20))
    role = create(:role, production: production, name: "Host")
    show.show_person_role_assignments.create!(role: show.available_roles.first || role, assignable: performing)
    shift.shift_assignments.create!(person: on_it)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def search(params)
    get manage_people_picker_search_path({ scope: "staff", shift_id: shift.id }.merge(params)), headers: { "X-Requested-With" => "XMLHttpRequest" }
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def row(doc, person)
    doc.at_css("[data-people-picker-row='Person_#{person.id}']")
  end

  it "lists everyone qualified, free first, each with their state, and the clashes in the pick" do
    doc = search({})
    expect(doc.text).to include("Qualified for Tech")
    names = doc.css("[data-people-picker-row] .truncate:first-child").map { |n| n.text.squish }
    expect(names).to eq([ "Free Fran", "Busy Bea", "Performing Pat", "Off Oli", "Already Al" ])
    expect(row(doc, off).text).to include("Unavailable")
    expect(row(doc, busy).text).to include("On another shift")
    expect(JSON.parse(row(doc, busy)["data-pick"])["staff"]["conflicts"].first).to include("role" => "Bar", "time_range" => "8:00 PM–11:00 PM")
    expect(row(doc, performing).text).to include("In a show")
    expect(JSON.parse(row(doc, performing)["data-pick"])["staff"]["cast"]).to eq([ "Late Show (8:00 PM)" ])
    expect(row(doc, on_it)["disabled"]).to be_present
    expect(row(doc, on_it).at_css("[data-people-picker-taken]").text).to eq("Assigned")
    expect(JSON.parse(row(doc, off)["data-pick"])["staff"]["verdict"]["status"]).to eq("blocked")
  end

  it "filters to who can work, or who's free for all of it, and searches by name" do
    expect(row(search(fit: "can_work"), off)).to be_nil
    expect(row(search(fit: "can_work"), free)).to be_present
    doc = search(fit: "free")
    expect(row(doc, off)).to be_nil
    expect(row(doc, free)).to be_present
    doc = search(q: "fran")
    expect(doc.css("[data-people-picker-row]").size).to eq(1)
    expect(search(q: "nobody").text).to include("No one is qualified for this role yet.")
  end
end
