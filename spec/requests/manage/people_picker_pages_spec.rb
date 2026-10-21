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
end
