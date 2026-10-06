# frozen_string_literal: true

require "rails_helper"

# Passes end to end (Tim, 2026-10-05): a manager builds one from two dates
# and puts it on sale; a buyer opens its page, picks how many and pays once
# for a seat at every show.
RSpec.describe "Ticket passes", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Twilight: Breaking Dawn") }
  let(:part_one) { TicketListing.create!(show: create(:show, production: production, date_and_time: 9.days.from_now.change(hour: 19)), status: "on_sale") }
  let(:part_two) { TicketListing.create!(show: create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 19)), status: "on_sale") }
  let!(:one_general) { part_one.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20) }
  let!(:two_general) { part_two.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20) }

  describe "managing passes" do
    before do
      create(:organization_role, :manager, user: superadmin, organization: org)
      post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
      get manage_path
    end

    it "builds a pass from two dates, puts it on sale and shows what each show counts" do
      get manage_new_ticket_pass_path
      expect(response.body).to include("the shows in the pass", "Twilight: Breaking Dawn")

      post manage_ticket_passes_path, params: { ticket_pass: {
        name: "Twilight Double Feature", price: "30", split: "regular_price", status: "on_sale",
        pass_shows_attributes: { "0" => { ticket_tier_id: one_general.id }, "1" => { ticket_tier_id: two_general.id } }
      } }
      pass = org.ticket_passes.last
      expect(response).to redirect_to(manage_ticket_pass_path(pass))
      expect(pass.pass_shows.count).to eq(2)

      get manage_ticket_pass_path(pass)
      expect(response.body).to include("Twilight Double Feature", "$15.00", "/tickets/starsandgarters/passes/twilight-double-feature")
      get manage_ticket_passes_path
      expect(response.body).to include("Twilight Double Feature", "On sale")
      get manage_edit_ticket_pass_path(pass)
      expect(response).to have_http_status(:ok)
    end

    it "says when typed shares don't add up, and never takes another organization's ticket type" do
      elsewhere = create(:ticket_listing).ticket_tiers.create!(name: "General", price_cents: 1_000, quantity: 5)
      post manage_ticket_passes_path, params: { ticket_pass: {
        name: "Bad pass", price: "30", split: "custom", status: "draft",
        pass_shows_attributes: { "0" => { ticket_tier_id: one_general.id, share: "10" }, "1" => { ticket_tier_id: elsewhere.id, share: "5" } }
      } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("add up to $10.00, not the pass price of $30.00")
      expect(TicketPassShow.where(ticket_tier: elsewhere)).to be_empty
    end

    it "shows the fair refund for part of a pass, with the full share one tap away" do
      pass = org.ticket_passes.create!(name: "Twilight Double Feature", price_cents: 3_000, status: "on_sale",
                                       pass_shows_attributes: [ { ticket_tier_id: one_general.id }, { ticket_tier_id: two_general.id } ])
      order = TicketCheckout.start_pass!(pass: pass, quantity: 1)
      TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_review")

      order.update!(buyer_name: "Bella Swan", buyer_email: "bella@example.com")
      get manage_ticket_listing_path(part_one)
      expect(response.body).to include("General (Twilight Double Feature pass)")

      get manage_ticket_order_refund_path(order.id, ticket_ids: order.tickets.pluck(:id), item_ids: [ "" ])
      expect(response.body).to include("at its regular price", "Refund the full share instead")

      get manage_ticket_order_refund_path(order.id, ticket_ids: order.tickets.pluck(:id), item_ids: [ "" ], reprice: "0")
      expect(response.body).to include("Refunding the full amount", "Price what they keep at regular")
    end

    it "can't open another organization's pass" do
      theirs = create(:organization).ticket_passes.create!(name: "Theirs", price_cents: 100)
      get manage_ticket_pass_path(theirs)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "buying one" do
    let!(:pass) do
      org.ticket_passes.create!(name: "Twilight Double Feature", price_cents: 3_000, status: "on_sale",
                                pass_shows_attributes: [ { ticket_tier_id: one_general.id }, { ticket_tier_id: two_general.id } ])
    end

    it "shows the shows, the all-in price against separately, and checks out once for both" do
      get tickets_pass_path(org: "starsandgarters", pass: pass.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Twilight Double Feature", "A pass for 2 shows",
                                       ActiveSupport::NumberHelper.number_to_currency(pass.all_in_price_cents / 100.0))

      post tickets_pass_checkout_path(org: "starsandgarters", pass: pass.slug), params: { quantity: 2 }
      order = TicketOrder.order(:id).first
      expect(response).to redirect_to(tickets_checkout_path(token: order.token))

      follow_redirect!
      expect(response.body).to include("2 × Twilight Double Feature", "Pay #{ActiveSupport::NumberHelper.number_to_currency(order.ticket_purchase.total_cents / 100.0)}")

      TicketPurchaseSettlement.settle!(order.ticket_purchase.reload, payment_intent_id: "pi_pass")
      get tickets_order_path(token: order.reload.token)
      expect(response.body).to include("Your Twilight Double Feature also covers", "See these tickets")
    end

    it "is on the box office, and on each of its shows' pages" do
      get tickets_box_office_path(org: "starsandgarters")
      expect(response.body).to include("Twilight Double Feature")
      get tickets_event_path(org: "starsandgarters", event: part_two.slug)
      expect(response.body).to include("Save with the pass", "Twilight Double Feature")
    end

    it "sends a buyer back with the reason when there aren't the seats" do
      two_general.update!(quantity: 1)
      post tickets_pass_checkout_path(org: "starsandgarters", pass: pass.slug), params: { quantity: 2 }

      expect(response).to redirect_to(tickets_pass_path(org: "starsandgarters", pass: pass.slug))
      expect(flash[:alert]).to include("doesn't have enough seats")
    end

    it "keeps a draft to superadmins" do
      pass.update!(status: "draft")
      get tickets_pass_path(org: "starsandgarters", pass: pass.slug)
      expect(response).to have_http_status(:not_found)
    end
  end
end
