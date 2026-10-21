# frozen_string_literal: true

require "rails_helper"

# A vacancy's invitees come through the shared People Picker (V1.1 plan
# §4, §5): the talent pool available first, then no answer, then
# unavailable, each saying so; who's cast, invited or can't make it is
# marked; Send is pinned to the bottom on a phone.
RSpec.describe "A vacancy's invite list", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }
  let(:role) { create(:role, production: production, name: "Improviser") }
  let!(:vacancy) { create(:role_vacancy, :with_vacated_by, show: show, role: role) }
  let(:people) { %w[Avery Blake Casey].map { |n| create(:person, name: "#{n} Performer").tap { |p| org.people << p } } }

  before do
    people.each { |p| create(:talent_pool_membership, talent_pool: production.talent_pool, member: p) }
    create(:show_availability, :unavailable, show: show, available_entity: people[0])
    create(:show_availability, :available, show: show, available_entity: people[2])
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "picks through the People Picker, listing the pool available first, and pins Send" do
    get manage_casting_vacancy_path(production, vacancy)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    picker = doc.at_css("[data-people-picker='vacancy-picker']")
    params = JSON.parse(picker["data-people-picker-params-value"])
    expect(params).to include("list" => "pool", "scope" => "members", "show_id" => show.id, "in_show" => "taken", "exclude_label" => "Can't make it")
    expect(params["exclude"]).to eq([ "#{vacancy.vacated_by_type}_#{vacancy.vacated_by_id}" ])
    expect(picker["data-people-picker-multi-value"]).to eq("true")
    expect(picker["data-action"]).to include("people-picker:pick->invite-picks#picked")
    add_all = doc.at_css("[data-vacancy-invitees] [data-action='click->invite-picks#addAll']")
    expect(JSON.parse(add_all["data-members"]).map { |m| m["name"] }).to eq([ "Casey Performer" ])
    expect(doc.at_css("[data-sticky-actions]").text).to include("Send Invitations")
    expect(doc.at_css("input[name='member_ids[]']")).to be_nil

    get manage_people_picker_search_path(params), headers: { "X-Requested-With" => "XMLHttpRequest" }
    body = response.body
    casey, blake, avery = body.index("Casey Performer"), body.index("Blake Performer"), body.index("Avery Performer")
    expect(casey).to be < blake
    expect(blake).to be < avery
    expect(body).to include(">Available</span>", ">Unavailable</span>")
  end
end
