# frozen_string_literal: true

require "rails_helper"

# The pages that pick people through the shared People Picker (V1.1 plan
# §5), each with its own sheet and listener, and none of their old search
# boxes.
RSpec.describe "Pages on the shared People Picker", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def picker(doc, id)
    wrapper = doc.at_css("[data-people-picker='#{id}']")
    expect(wrapper).to be_present
    expect(wrapper["data-people-picker-url-value"]).to eq(manage_people_picker_search_path)
    [ wrapper, JSON.parse(wrapper["data-people-picker-params-value"]) ]
  end

  it "sign-up assign and the roster add through it, to a slot or the queue" do
    show = create(:show, production: production, date_and_time: 3.days.from_now)
    form = create(:sign_up_form, production: production, show: show, slot_selection_mode: "admin_assigns")
    instance = create(:sign_up_form_instance, sign_up_form: form, show: show)
    create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance, position: 1)

    get manage_assign_signups_form_path(production, form, instance_id: instance.id)
    doc = Nokogiri::HTML(response.body)
    wrapper, params = picker(doc, "sign-up-picker")
    expect(params).to include("scope" => "people", "production_id" => production.id)
    expect(wrapper["data-action"]).to include("people-picker:pick->add-sign-up-person#picked")
    expect(doc.at_css("[data-add-sign-up-person-target='searchInput']")).to be_nil

    get manage_signups_form_path(production, form)
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("[data-people-picker='sign-up-picker']")).to be_present
  end

  it "the talent pool adds people, groups, outsiders and invitations through it" do
    get manage_casting_settings_section_path(production_id: production, section: "talent_pool")
    doc = Nokogiri::HTML(response.body)
    wrapper, params = picker(doc, "talent-pool-picker")
    expect(params).to include("scope" => "members", "talent_pool_id" => production.talent_pool.id, "outside" => "1", "invite" => "1", "invite_name" => "1")
    expect(wrapper["data-action"]).to include("talent-pool-inline#picked")
    expect(doc.at_css("[data-talent-pool-inline-target='addModal']")).to be_nil
  end

  it "the production team adds people with accounts, outsiders and invitations through it" do
    get edit_manage_production_path(production)
    doc = Nokogiri::HTML(response.body)
    wrapper, params = picker(doc, "team-picker")
    expect(params).to include("scope" => "users", "production_id" => production.id, "outside" => "1", "invite" => "1")
    expect(wrapper["data-action"]).to include("production-team-search#picked")
    trigger = doc.at_css("[data-people-picker-trigger-id-value='team-picker']")
    expect(trigger.text).to include("Choose a person")
    expect(doc.at_css("[data-production-team-search-target='input']")).to be_nil
  end

  it "a questionnaire invites several people through it, skipping those invited" do
    questionnaire = create(:questionnaire, production: production)
    invited = create(:person, name: "Invited Ivy").tap { |p| org.people << p }
    create(:person, name: "Waiting Wren").tap { |p| org.people << p }
    questionnaire.questionnaire_invitations.create!(invitee: invited)

    get manage_contacts_questionnaire_path(questionnaire)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    wrapper, params = picker(doc, "questionnaire-picker")
    expect(wrapper["data-people-picker-multi-value"]).to eq("true")
    expect(params["exclude"]).to eq([ invited.id ])
    expect(wrapper["data-action"]).to include("questionnaire-person-search#picked")
    expect(doc.at_css("[data-questionnaire-person-search-target='dropdown']")).to be_nil
  end

  it "the door and a show's Visibility find anyone with an account through it, and still take an email to invite" do
    get manage_ticketing_settings_section_path(section: "door")
    doc = Nokogiri::HTML(response.body)
    wrapper, params = picker(doc, "door-picker")
    expect(params).to include("scope" => "users", "outside" => "1", "invite" => "1", "invite_name" => "1", "exclude_label" => "Has the door")
    expect(doc.at_css("[data-door-access-search-target='searchSection'] [data-people-picker-trigger-id-value='door-picker']")).to be_present
    expect(doc.at_css("[data-door-access-search-target='email']")).to be_present
    expect(doc.at_css("[data-door-access-search-target='input']")).to be_nil
    card = doc.at_css("[data-door-access-search-picker-value='door-picker']")
    expect(card["data-door-access-search-invite-url-value"]).to eq(manage_ticketing_door_invite_path)

    listing = create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 3.days.from_now))
    get manage_ticket_listing_visibility_path(listing)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    _, params = picker(doc, "viewer-picker")
    expect(params).to include("scope" => "users", "exclude_label" => "Sees the sales")
    expect(doc.at_css("[data-door-access-search-picker-value='viewer-picker']")["data-door-access-search-invite-url-value"]).to eq(manage_ticket_listing_visibility_invite_path(listing))
  end

  it "a casting table's talent pool adds people and groups through it, listing the organization first" do
    table = CastingTable.create!(organization: org, name: "Spring Cast", status: "draft", created_by: owner)
    member = create(:person, name: "Already Al").tap { |p| org.people << p }
    create(:person, name: "New Nia").tap { |p| org.people << p }
    table.casting_table_members.create!(memberable: member)

    get manage_casting_table_edit_members_path(table)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    wrapper, params = picker(doc, "table-picker")
    expect(params).to include("scope" => "members", "list" => "org", "exclude" => [ "Person_#{member.id}" ], "exclude_label" => "In this table")
    expect(doc.at_css("[data-casting-table-members-target='form']")["action"]).to eq(manage_casting_table_add_member_path(table))
    expect(doc.text).not_to include("New Nia")

    get manage_people_picker_search_path, params: params.merge(q: "")
    body = Nokogiri::HTML(response.body)
    expect(body.text).to include("In your organization", "New Nia")
    expect(body.at_css("[data-people-picker-row='Person_#{member.id}'] [data-people-picker-taken]").text).to eq("In this table")
  end

  it "compose's Individuals step adds people through it on every page that composes" do
    get manage_path # production mode: compose is there
    get messages_path
    doc = Nokogiri::HTML(response.body)
    wrapper, params = picker(doc, "compose-picker")
    expect(params).to include("scope" => "people")
    expect(params).not_to have_key("production_id")
    expect(wrapper["data-people-picker-multi-value"]).to eq("true")
    expect(doc.at_css("#compose-message-modal")["data-action"]).to include("people-picker:pick@window->compose-message#picked")
    expect(doc.at_css("[data-compose-message-target='personSearchInput']")).to be_nil
    expect(doc.at_css("[data-action='click->compose-message#openPeoplePicker']")).to be_present

    get production_manage_messages_path(production)
    _, params = picker(Nokogiri::HTML(response.body), "compose-picker")
    expect(params).to include("production_id" => production.id)
  end
end
