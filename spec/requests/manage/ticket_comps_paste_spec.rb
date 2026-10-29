# frozen_string_literal: true

require "rails_helper"

# The Comps modal's "Paste a list" tab (Tim, 2026-10-29): a guest list from a
# spreadsheet or CSV, one ticket type and one "email them" for the batch, a
# preview of who gets what against the comps, seats and allowance left, then
# all of them given in one go, or none.
RSpec.describe "Giving comps from a pasted list", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19, min: 30)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 6) }
  let!(:vip) { listing.ticket_tiers.create!(name: "VIP", price_cents: 4_000, quantity: 10) }
  let(:back) { manage_ticket_listing_path(listing, anchor: "guests") }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: owner, organization: org)
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  def comps = listing.ticket_orders.where(channel: "comp")

  describe "a manager on the show's page" do
    before { sign_in(owner) }

    it "offers the paste tab beside the one-person form" do
      get manage_ticket_listing_path(listing)
      expect(response.body).to include("One person", "Paste a list", manage_ticket_listing_comps_preview_path(listing),
                                       'id="comps-modal-paste-form"', 'name="mode"', 'id="comp_paste_text"', 'id="comp_paste_tier_id"')
      # The paste tab's Give is never a disabled button: it's Preview until the preview is ready.
      expect(response.body).not_to match(/data-comps-paste-target="give"[^>]*disabled/)
    end

    it "previews every line format, skips a CSV header and repeats, and flags the lines it can't read" do
      post manage_ticket_listing_comps_preview_path(listing), params: { tier_id: general.id, email_them: "0", text: <<~LIST }
        Name,Email,Tickets
        Dana Scully,dana@example.com,2
        Fox Mulder\tfox@example.com
        Monica Reyes <monica@example.com>
        tkwan@example.com
        Walter Skinner, 1, VIP
        Dana again, DANA@example.com
        Alvin Kersh, kersh@example
      LIST
      expect(response).to have_http_status(:ok)
      html = response.body
      expect(html).to include('data-comps-paste-ready="0"', "Dana Scully", "Fox Mulder", "Monica Reyes", "tkwan@example.com", "Walter Skinner",
                              "6 comps for 5 people", "Line 8:", "kersh@example isn&#39;t an email address.", "Line 7: Same email as line 2, so left out.")
      expect(html).not_to include("Name,Email,Tickets")
      expect(html).to match(/1 &times; VIP/)
      expect(comps.count).to eq(0)

      post manage_ticket_listing_comps_preview_path(listing), params: { tier_id: general.id, email_them: "0", text: "Dana Scully, dana@example.com, 2\nFox Mulder" }
      expect(response.body).to include('data-comps-paste-ready="3"', "3 comps for 2 people", "General: 6 seats left")
    end

    it "gives the whole list in one go" do
      expect {
        post manage_ticket_listing_comps_path(listing),
             params: { mode: "paste", tier_id: general.id, email_them: "1", note: "Press night",
                       text: "Dana Scully, dana@example.com, 2\nFox Mulder <fox@example.com>\nWalter Skinner, walter@example.com, 1, VIP" }
      }.to have_enqueued_job(TicketOrderConfirmationJob).exactly(3).times
      expect(response).to redirect_to(back)
      expect(flash[:notice]).to eq("Gave 4 tickets to 3 people. They're on the guest list.")
      expect(comps.order(:id).map { |o| [ o.buyer_name, o.buyer_email, o.note, o.issued_by_id, o.tickets.map { |t| t.ticket_tier.name } ] }).to eq([
        [ "Dana Scully", "dana@example.com", "Press night", owner.id, %w[General General] ],
        [ "Fox Mulder", "fox@example.com", "Press night", owner.id, %w[General] ],
        [ "Walter Skinner", "walter@example.com", "Press night", owner.id, %w[VIP] ]
      ])
    end

    it "gives none of a list that's more than the seats left" do
      text = "Dana Scully, 4\nFox Mulder, 3"
      post manage_ticket_listing_comps_preview_path(listing), params: { tier_id: general.id, text: text }
      expect(response.body).to include('data-comps-paste-ready="0"', "General has 6 seats left, and this list needs 7.")

      post manage_ticket_listing_comps_path(listing), params: { mode: "paste", tier_id: general.id, text: text }
      expect(response).to redirect_to(back)
      expect(flash[:alert]).to eq("General has 6 seats left, and this list needs 7.")
      expect(comps.count).to eq(0)
    end

    it "gives none of a list with a line it can't read, or past the date's comps" do
      post manage_ticket_listing_comps_path(listing), params: { mode: "paste", tier_id: general.id, text: "Dana Scully\nFox, fox@example" }
      expect(flash[:alert]).to eq("Line 2: fox@example isn't an email address.")
      expect(comps.count).to eq(0)

      listing.update!(own_comps: true, comps_limit: "fixed", comps_per_show: 2)
      post manage_ticket_listing_comps_path(listing), params: { mode: "paste", tier_id: general.id, text: "Dana Scully\nFox Mulder\nWalter Skinner" }
      expect(flash[:alert]).to eq("This date has 2 comps left to give, and this list is 3.")
      expect(comps.count).to eq(0)
    end

    it "needs an email on every line to email them their tickets" do
      text = "Dana Scully, dana@example.com\nFox Mulder"
      post manage_ticket_listing_comps_preview_path(listing), params: { tier_id: general.id, email_them: "1", text: text }
      expect(response.body).to include('data-comps-paste-ready="0"', "Line 2:", "No email to send Fox Mulder their tickets.", "each gets their tickets by email")

      expect {
        post manage_ticket_listing_comps_path(listing), params: { mode: "paste", tier_id: general.id, email_them: "1", text: text }
      }.not_to have_enqueued_job(TicketOrderConfirmationJob)
      expect(flash[:alert]).to eq("Line 2: No email to send Fox Mulder their tickets.")
      expect(comps.count).to eq(0)

      # Handed over instead: no emails needed, none sent.
      expect {
        post manage_ticket_listing_comps_path(listing), params: { mode: "paste", tier_id: general.id, email_them: "0", text: text }
      }.not_to have_enqueued_job(TicketOrderConfirmationJob)
      expect(comps.count).to eq(2)
    end
  end

  describe "a production team manager within their allowance" do
    let(:manager) { create(:user, email_address: "clay@sg.example", password: password) }
    let(:sale) { manage_production_sale_path(production, listing, anchor: "guests") }

    before do
      TicketingProfile.for(org).update!(team_comps_limit: "fixed", team_comps_per_show: 3)
      create(:person, user: manager, name: "Clay Smith").tap { |p| manager.update!(default_person: p) }
      create(:organization_role, user: manager, organization: org, company_role: "member")
      ProductionPermission.create!(user: manager, production: production, role: "manager")
      sign_in(manager)
    end

    it "counts the whole list against the allowance" do
      get manage_production_sale_path(production, listing)
      expect(response.body).to include("Paste a list", manage_production_sale_comps_preview_path(production, listing))

      text = "Dana Scully, 2\nFox Mulder, 2"
      post manage_production_sale_comps_preview_path(production, listing), params: { tier_id: general.id, text: text }
      expect(response.body).to include('data-comps-paste-ready="0"', "You can give 3 more comps for this date, and this list is 4.")

      post manage_production_sale_comps_path(production, listing), params: { mode: "paste", tier_id: general.id, text: text }
      expect(response).to redirect_to(sale)
      expect(flash[:alert]).to eq("You can give 3 more comps for this date, and this list is 4.")
      expect(comps.count).to eq(0)

      post manage_production_sale_comps_path(production, listing), params: { mode: "paste", tier_id: general.id, text: "Dana Scully, 2\nFox Mulder" }
      expect(flash[:notice]).to eq("Gave 3 tickets to 2 people. They're on the guest list.")
      expect(comps.where(issued_by: manager).count).to eq(2)

      # The allowance used up: no more, one at a time or pasted.
      post manage_production_sale_comps_path(production, listing), params: { mode: "paste", tier_id: general.id, text: "Walter Skinner" }
      expect(flash[:alert]).to eq("You can't give comps for this date.")
      expect(comps.count).to eq(2)
    end
  end
end
