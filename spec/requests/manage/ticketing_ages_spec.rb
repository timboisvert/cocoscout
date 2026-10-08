# frozen_string_literal: true

require "rails_helper"

# A minimum age (Tim, 2026-10-07): set on a production's Sales & page tab,
# overridden on a date's Page tab, and said on the ticket page, at checkout,
# on the buyer's order page, in their emails and at the door.
RSpec.describe "Ticketing ages", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let(:show_at) { Time.zone.local(2026, 11, 6, 21, 0) }
  let(:show) { create(:show, production: production, date_and_time: show_at) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
  end

  def sign_in
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def fresh_listing
    TicketListing.find(listing.id)
  end

  describe AgeLimit do
    it "says the age, and turns the choice back into what's stored" do
      expect([ AgeLimit.words(21), AgeLimit.label(21), AgeLimit.short(21), AgeLimit.words(nil), AgeLimit.words(0) ])
        .to eq([ "Ages 21 and over", "21 and over", "21+", nil, nil ])
      expect(AgeLimit.value_for("21", nil)).to eq(21)
      expect(AgeLimit.value_for("all", nil)).to be_nil
      expect(AgeLimit.value_for("all", nil, inherit: true)).to eq(0)
      expect(AgeLimit.value_for("production", nil, inherit: true)).to be_nil
      expect(AgeLimit.value_for("other", "16")).to eq(16)
      expect([ AgeLimit.value_for("other", "0"), AgeLimit.value_for("other", "abc"), AgeLimit.value_for("19", nil),
               AgeLimit.value_for("production", nil) ]).to all(eq(:invalid))
      expect([ AgeLimit.choice_for(nil), AgeLimit.choice_for(nil, inherit: true), AgeLimit.choice_for(0, inherit: true),
               AgeLimit.choice_for(25), AgeLimit.choice_for(16) ]).to eq(%w[all production all 25 other])
    end
  end

  it "is set on the production, and a date can follow it, say all ages, or set its own" do
    setup = ProductionTicketing.for(production)
    sign_in

    get manage_edit_production_ticketing_path(production, section: "sales")
    expect(response.body).to include("Ages", "All ages", "18 and over", "21 and over", "25 and over", "Another age", "Anything else about ages")

    patch manage_update_production_ticketing_path(production, section: "sales"),
          params: { production_ticketing: { age_choice: "21", age_other: "", age_note: "" } }
    expect(setup.reload.minimum_age).to eq(21)
    expect(fresh_listing.effective_minimum_age).to eq(21)
    expect(fresh_listing.age_words).to eq("Ages 21 and over")

    patch manage_update_production_ticketing_path(production, section: "sales"),
          params: { production_ticketing: { age_choice: "other", age_other: "120" } }
    expect(flash[:alert]).to eq("Type an age from 1 to 99.")
    expect(setup.reload.minimum_age).to eq(21)

    get manage_edit_ticket_listing_path(listing, section: "page")
    expect(response.body).to include("Same as the production", "Ages 21 and over")

    patch manage_ticket_listing_path(listing), params: { section: "page", ticket_listing: { age_choice: "all", age_note: "" } }
    expect(listing.reload.minimum_age).to eq(0)
    expect(fresh_listing.effective_minimum_age).to be_nil

    patch manage_ticket_listing_path(listing), params: { section: "page", ticket_listing: { age_choice: "other", age_other: "16", age_note: "Under 16 with a parent" } }
    expect(fresh_listing.age_words).to eq("Ages 16 and over · Under 16 with a parent")

    patch manage_ticket_listing_path(listing), params: { section: "page", ticket_listing: { age_choice: "production", age_note: "" } }
    expect(listing.reload.minimum_age).to be_nil
    expect(fresh_listing.effective_minimum_age).to eq(21)

    patch manage_update_production_ticketing_path(production, section: "sales"), params: { production_ticketing: { age_choice: "all" } }
    expect(setup.reload.minimum_age).to be_nil
    expect(fresh_listing.age_words).to be_nil
  end

  it "is said on the ticket page, at checkout, on the order, in the email and at the door" do
    ProductionTicketing.for(production).update!(minimum_age: 21)

    travel_to(show_at - 3.days) do
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).to include("Ages 21 and over", %("typicalAgeRange":"21-"))

      post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { general.id => 1 } }
      order = TicketOrder.order(:id).last
      get tickets_checkout_path(token: order.token)
      expect(response.body).to include(%(<span class="font-medium text-gray-900">Ages 21 and over</span>))

      order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com")
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_ages")
      get tickets_order_path(token: order.token)
      expect(response.body).to include("Ages 21 and over")

      mail = TicketOrderMailer.confirmation(order.reload)
      body = mail.html_part&.body.to_s.presence || mail.body.to_s
      expect(body).to include(">Ages</div>", ">21 and over</div>")
      reminder = TicketOrderMailer.reminder(order)
      expect(reminder.html_part&.body.to_s.presence || reminder.body.to_s).to include(">21 and over</div>")

      sign_in
      get door_path(listing)
      expect(response.body).to include("Ages 21+")
    end
  end

  it "says nothing about ages when anyone can come" do
    travel_to(show_at - 3.days) do
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).not_to include("and over", "typicalAgeRange")
      mail = TicketOrderMailer.confirmation(TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "1" }).tap { |o|
        o.update!(buyer_name: "Fox Mulder", buyer_email: "fox@example.com")
        TicketOrderSettlement.settle!(o, payment_intent_id: "pi_all")
      }.reload)
      expect(mail.html_part&.body.to_s.presence || mail.body.to_s).not_to include(">Ages</div>")
    end
  end
end
