# frozen_string_literal: true

require "rails_helper"

# The cast's Tickets card on a show's page in My Shows & Events (Tim,
# 2026-10-16): the count and this date's link to share, by Who sees sales
# (TicketSalesAccess). Never names, money or a QR code. A production team
# manager at Everything also gets the comps and a button to the date's
# sales page.
RSpec.describe "My show page: Tickets for the cast", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 3_000, quantity: 80) }
  let(:performer) { create(:user, password: password) }
  let!(:person) { create(:person, user: performer, name: "Jamie Cruz").tap { |p| performer.update!(default_person: p) } }
  let(:profile) { TicketingProfile.for(org) }

  before do
    profile.update!(enabled: true)
    create(:organization_role, :manager, user: owner, organization: org)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "2" })
    order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com", buyer_phone: "312-555-0100")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")
    TicketComps.give!(listing, [ TicketComps::Guest.new(name: "Abe Comp", email: nil, tier: general, quantity: 1) ], by: owner, email_them: false)
  end

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def date_link
    "/t/#{ShortLink.canonical_for!(production).code}/#{ShortLink.date_suffix(show)}"
  end

  it "shows everyone in the talent pool the count and this date's link, with no names, money, comps or QR" do
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person)
    sign_in(performer)
    get my_show_path(show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-tickets-card", ">Tickets<", "2 of 79 sold", date_link, "Your link for this date")
    expect(response.body).not_to include("Dana Scully", "dana@example.com", "1 comp", "qr-code", "$30", "Ticket sales")
  end

  it "reaches only the people cast in the date when the setting says so, and nobody at Nothing" do
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person)
    profile.update!(cast_sales: "show_cast")
    sign_in(performer)
    get my_show_path(show)
    expect(response.body).not_to include("data-tickets-card")

    create(:show_person_role_assignment, show: show, assignable: person, role: create(:role, production: production))
    show.update!(casting_finalized_at: Time.current)
    get my_show_path(show)
    expect(response.body).to include("data-tickets-card", "2 of 79 sold")

    profile.update!(cast_sales: "nothing")
    get my_show_path(show)
    expect(response.body).not_to include("data-tickets-card")
  end

  it "shows nothing without Pro or with the box office closed" do
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person)
    sign_in(performer)
    profile.update!(enabled: false)
    get my_show_path(show)
    expect(response.body).not_to include("data-tickets-card")

    profile.update!(enabled: true)
    org.update!(comped_indefinitely: false)
    get my_show_path(show)
    expect(response.body).not_to include("data-tickets-card")
  end

  it "gives a production team manager the comps count and a Ticket sales button to the Production Dashboard" do
    create(:organization_role, user: performer, organization: org, company_role: "member")
    ProductionPermission.create!(user: performer, production: production, role: "manager")
    sign_in(performer)
    get my_show_path(show)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-tickets-card", "2 of 79 sold", "1 comp", "Ticket sales", manage_production_sale_path(production, listing))
    expect(response.body).not_to include("Dana Scully")
  end
end
