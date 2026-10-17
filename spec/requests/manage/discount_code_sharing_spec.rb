# frozen_string_literal: true

require "rails_helper"

# Discount codes shared with the people who see a date's sales (Tim,
# 2026-10-17): each code says who sees it beside the ticket link, the
# production team and the cast (the default), the team only, or nobody.
RSpec.describe "Discount codes shared with the team and the cast", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19, min: 30)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 3_000, quantity: 80) }
  let(:manager) { create(:user, email_address: "clay@sg.example", password: password) }
  let(:performer) { create(:user, email_address: "jamie@sg.example", password: password) }
  let!(:person) { create(:person, user: performer, name: "Jamie Cruz").tap { |p| performer.update!(default_person: p) } }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    create(:organization_role, :manager, user: owner, organization: org)
    create(:organization_role, user: manager, organization: org, company_role: "member")
    ProductionPermission.create!(user: manager, production: production, role: "manager")
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person)
  end

  def sign_in(user, org_too: true)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id) if org_too
  end

  it "lets a manager choose who sees a code when adding it, and change it after" do
    sign_in(owner)
    get manage_edit_production_ticketing_path(production, section: "codes")
    expect(response.body).to include("Share it with", "Production team and cast", "Production team only", "Nobody")
    expect(response.body).to match(/checked="checked"[^>]*id="ticket_discount_code_shared_with_team_and_cast"/)

    post manage_production_ticketing_codes_path(production), params: { ticket_discount_code: { code: "friends20", kind: "percent", amount: "20", shared_with: "team" } }
    code = org.ticket_discount_codes.find_by!(code: "FRIENDS20")
    expect(code.shared_with).to eq("team")

    patch manage_production_ticketing_code_path(production, code_id: code.id), params: { shared_with: "nobody" }
    expect(response).to redirect_to(manage_edit_production_ticketing_path(production, section: "codes"))
    expect(flash[:notice]).to eq("FRIENDS20 is shared with nobody.")
    expect(code.reload.shared_with).to eq("nobody")

    post manage_ticket_listing_codes_path(listing), params: { ticket_discount_code: { code: "tonight5", kind: "fixed", amount: "5" } }
    expect(org.ticket_discount_codes.find_by!(code: "TONIGHT5").shared_with).to eq("team_and_cast")
  end

  it "adds codes from a modal, and a date on its own codes stops taking the production's" do
    sign_in(owner)
    org.ticket_discount_codes.create!(production: production, code: "EVERYONE", kind: "percent", percent: 20)
    get manage_edit_production_ticketing_path(production, section: "codes")
    expect(response.body).to include('id="add-code-modal"', "Add a discount code", "every date of Stargazers", "EVERYONE", 'data-modal-id="add-code-modal"')

    get manage_edit_ticket_listing_path(listing, section: "codes")
    expect(response.body).to include("Stargazers&#39; codes:", "EVERYONE (20% off)", "This date's own codes", "No codes of its own yet", "<fieldset disabled", 'id="add-code-modal"')
    expect(TicketCheckout.find_discount(listing, "EVERYONE")).to be_present

    patch manage_ticket_listing_path(listing, section: "codes"), params: { ticket_listing: { own_codes: "1" } }
    expect(response).to redirect_to(manage_edit_ticket_listing_path(listing, section: "codes"))
    expect(flash[:notice]).to eq("This date uses its own codes; Stargazers' don't work on it.")
    expect(listing.reload.own_codes).to be(true)
    expect(TicketCheckout.find_discount(listing, "EVERYONE")).to be_nil
    post manage_ticket_listing_codes_path(listing), params: { ticket_discount_code: { code: "tonight", kind: "fixed", amount: "3" } }
    expect(TicketCheckout.find_discount(listing, "TONIGHT")).to be_present
    get manage_edit_ticket_listing_path(listing, section: "codes")
    expect(response.body).to include("TONIGHT", "$3.00 off")
    expect(response.body).not_to include("<fieldset disabled")
    expect(TicketDiscountCode.shared_for(listing).map(&:code)).to eq([ "TONIGHT" ])

    patch manage_ticket_listing_path(listing, section: "codes"), params: { ticket_listing: { own_codes: "0" } }
    expect(listing.reload.own_codes).to be(false)
    expect(TicketCheckout.find_discount(listing, "EVERYONE")).to be_present
    expect(TicketDiscountCode.shared_for(listing).map(&:code)).to eq(%w[EVERYONE TONIGHT])
  end

  it "shows the production team their codes, the cast only the ones shared with everyone, and nobody the rest" do
    org.ticket_discount_codes.create!(production: production, code: "EVERYONE", kind: "percent", percent: 20, shared_with: "team_and_cast")
    org.ticket_discount_codes.create!(production: production, code: "TEAMONLY", kind: "fixed", amount_cents: 500, shared_with: "team")
    org.ticket_discount_codes.create!(production: production, code: "SECRET", kind: "fixed", amount_cents: 1_000, shared_with: "nobody")
    org.ticket_discount_codes.create!(ticket_listing: listing, code: "TONIGHT", kind: "fixed", amount_cents: 300, shared_with: "team_and_cast")
    org.ticket_discount_codes.create!(production: production, code: "USEDUP", kind: "fixed", amount_cents: 300, shared_with: "team_and_cast", active: false)

    sign_in(manager)
    get manage_production_show_path(production, show)
    expect(response.body).to include("data-shared-codes", "EVERYONE", "TEAMONLY", "TONIGHT", "20% off", "$5.00 off")
    expect(response.body).not_to include("SECRET", "USEDUP")
    get manage_production_sales_path(production)
    expect(response.body).to include("EVERYONE", "TEAMONLY")
    expect(response.body).not_to include("SECRET", "TONIGHT")
    get manage_production_sale_path(production, listing)
    expect(response.body).to include("EVERYONE", "TEAMONLY", "TONIGHT")
    expect(response.body).not_to include("SECRET")
    get manage_production_path(production)
    expect(response.body).to include("data-shared-codes", "EVERYONE", "TEAMONLY")

    sign_in(performer, org_too: false)
    get my_show_path(show)
    expect(response.body).to include("data-shared-codes", "EVERYONE", "TONIGHT", "20% off")
    expect(response.body).not_to include("TEAMONLY", "SECRET")
    get my_production_path(production)
    expect(response.body).to include("data-shared-codes", "EVERYONE")
    expect(response.body).not_to include("TEAMONLY", "TONIGHT")
  end
end
