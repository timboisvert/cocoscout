# frozen_string_literal: true

require "rails_helper"

# A vacancy on a phone (V1.1 plan §4): the people to invite, sorted by what
# they said about the date, and Send pinned to the bottom.
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

  it "lists who said they're available first, then no answer, then unavailable, each saying so" do
    get manage_casting_vacancy_path(production, vacancy)
    expect(response).to have_http_status(:ok)
    body = response.body
    casey, blake, avery = body.index("Casey Performer"), body.index("Blake Performer"), body.index("Avery Performer")
    expect(casey).to be < blake
    expect(blake).to be < avery
    expect(body).to include(">Available</span>", ">Unavailable</span>")
    expect(Nokogiri::HTML(body).at_css("[data-sticky-actions]").text).to include("Send Invitations")
  end
end
