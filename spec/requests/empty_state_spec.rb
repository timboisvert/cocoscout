# frozen_string_literal: true

require "rails_helper"

# The one empty-list component (shared/_empty_state; Tim, 2026-10-21: the
# "You're all caught up" box on My Tasks is the model for every empty list,
# in both modes): a dashed box with a gray icon, a short title, a line that
# says what would fill it, and sometimes the button that does.
RSpec.describe "The empty-state component", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:organization) { create(:organization, :pro, name: "Starlight Theater", owner: user) }
  let!(:role) { create(:organization_role, :manager, user: user, organization: organization) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:production) { create(:production, organization: organization) }
  let(:pool) { create(:talent_pool, production: production) }

  before do
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: organization.id)
  end

  def empty_states(body)
    Nokogiri::HTML(body).css("[data-empty-state]")
  end

  it "is the box on My Tasks, My Shows & Events, auditions, payments and the inbox" do
    TalentPoolMembership.create!(talent_pool: pool, member: person)
    get my_tasks_path
    expect(empty_states(response.body).map { |e| e["data-empty-state"] }).to include("check")
    get my_shows_path
    expect(empty_states(response.body).map { |e| e["data-empty-state"] }).to include("calendar")
    get my_auditions_path
    expect(response.body).to include("No upcoming auditions")
    expect(empty_states(response.body)).to be_present
    get my_payments_path
    expect(empty_states(response.body).map { |e| e["data-empty-state"] }).to include("money")
    get messages_path
    expect(empty_states(response.body).map { |e| e["data-empty-state"] }).to include("inbox")
    get notifications_path
    expect(empty_states(response.body).map { |e| e["data-empty-state"] }).to include("bell")
  end

  it "is the box on the production-mode lists, with the button that fills them" do
    get manage_productions_path
    box = empty_states(response.body).first
    expect(box).to be_present
    expect(box.text).to include("No productions yet", "Create your first production")
    expect(box.at_css("a[href='#{manage_productions_wizard_path}']")["class"]).to include("bg-pink")

    get manage_contracts_path
    expect(empty_states(response.body).first.text).to include("No contracts yet", "New contract")
    get manage_contractors_path
    expect(empty_states(response.body).first.text).to include("No contractors yet")
    get manage_contacts_path
    expect(empty_states(response.body).first.text).to include("No people or groups yet")
    get manage_shows_path
    expect(empty_states(response.body)).to be_present
  end

  it "draws a dashed box with the icon, or a plain compact one inside a card" do
    TalentPoolMembership.create!(talent_pool: pool, member: person)
    get my_tasks_path
    box = empty_states(response.body).first
    expect(box["class"]).to include("border-dashed")
    expect(box.at_css("svg")).to be_present
    expect(box.at_css("h3").text).to be_present

    get my_payments_path
    compact = empty_states(response.body).find { |e| e["data-empty-state"] == "check" }
    expect(compact["class"]).not_to include("border-dashed")
  end
end
