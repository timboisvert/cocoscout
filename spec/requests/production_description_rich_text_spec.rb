# frozen_string_literal: true

require "rails_helper"

# A production's description is rich text everywhere it's written — the
# production's settings, a contract's Change the basic info, the ticketing
# setup's page words and a date's own — and keeps its formatting everywhere
# it's read, with plain words where only words fit (Tim, 2026-11-04).
RSpec.describe "A production's description is rich text", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:words) { "<div>Every scene turns into an <strong>animal</strong>.<br>Bring a friend.</div>" }
  let(:production) do
    create(:production, organization: org, name: "Improvised Animorphs", description: words,
                        public_profile_enabled: true, public_key: "animorphs")
  end
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30), public_profile_visible: true) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  it "keeps its formatting on the ticket page and the public page, with plain words for search engines" do
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include("<strong>animal</strong>", "Bring a friend")
    expect(response.body).to include('<meta name="description" content="Every scene turns into an animal. Bring a friend.">')
    data = JSON.parse(response.body[%r{<script type="application/ld\+json">(.*?)</script>}m, 1])
    expect(data["description"]).to eq("Every scene turns into an animal. Bring a friend.")

    get public_profile_path("animorphs")
    expect(response.body).to include("<strong>animal</strong>")
  end

  it "describes the listing in plain words, with the HTML alongside" do
    payload = Ticketing::ListingPayload.for(listing)
    expect(payload[:description]).to eq("Every scene turns into an animal.\nBring a friend.")
    expect(payload[:description_html]).to include("<strong>animal</strong>")
  end

  it "lets a date's own words and the ticketing's override the production's, formatting kept" do
    production.create_production_ticketing!(organization: org, description: "<div>The <em>Halloween</em> run.</div>")
    expect(TicketListing.find(listing.id).effective_description.to_plain_text).to eq("The Halloween run.")

    listing.update!(description: "<div>Tonight: <em>costumes</em> welcome.</div>")
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include("<em>costumes</em>")
    expect(response.body).not_to include("Halloween", "<strong>animal</strong>")
  end

  describe "where it's written" do
    before { sign_in(owner) }

    it "is the editor on the production's settings, the ticketing setup and a date's page" do
      get edit_manage_production_path(production)
      expect(response.body).to include('<trix-editor', 'name="production[description]"')

      production.create_production_ticketing!(organization: org)
      get manage_edit_production_ticketing_path(production, section: "sales")
      expect(response.body).to include('<trix-editor', 'name="production_ticketing[description]"')
      # The production's words, faint in the box, are plain.
      expect(response.body).to include('placeholder="Every scene turns into an animal. Bring a friend."')

      get manage_edit_ticket_listing_path(listing, section: "page")
      expect(response.body).to include('<trix-editor', 'name="ticket_listing[description]"')
    end

    it "is the editor in a contract's Change the basic info, and the words saved keep their formatting" do
      contracted = create(:production, organization: org, production_type: "third_party", name: "Nuns4Fun", description: "Old words")
      contract = create(:contract, :active, organization: org, production: contracted, contractor_name: "Habit Theater", production_name: "Nuns4Fun")

      get amend_basics_manage_contract_path(contract)
      expect(response.body).to include("<trix-editor", 'name="description"', "Old words")

      post apply_amend_basics_manage_contract_path(contract),
           params: { production_name: "Nuns4Fun", description: "<div>Two nuns, <strong>one</strong> stage.</div>" }
      expect(flash[:notice]).to eq("Updated the description.")
      expect(contracted.reload.description.to_s).to include("<strong>one</strong>")

      # The editor's empty markup is no description.
      post apply_amend_basics_manage_contract_path(contract), params: { production_name: "Nuns4Fun", description: "<div><br></div>" }
      expect(flash[:notice]).to eq("Updated the description.")
      expect(contracted.reload.description).to be_blank

      post apply_amend_basics_manage_contract_path(contract), params: { production_name: "Nuns4Fun", description: "" }
      expect(flash[:notice]).to eq("Nothing to change.")
    end

    it "is the editor in the new-production wizard, and the words it saves keep their formatting" do
      get manage_productions_wizard_path
      expect(response.body).to include("<trix-editor", 'name="description"')
    end
  end
end
