# frozen_string_literal: true

require "rails_helper"

# A production's Links page: its one code, named links for posters and posts,
# and what each one sold. A buyer who arrives through a link is remembered on
# the order.
RSpec.describe "Ticketing links", type: :request do
  let(:password) { "Password123!" }
  let(:admin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: admin) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let(:show) { create(:show, production: production, date_and_time: Time.zone.local(2026, 10, 17, 19, 30)) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }
  let(:code) { production.reload.short_link.code }

  # The show is on Oct 17, 2026; hold the clock before it so the date never passes.
  before { travel_to Time.zone.local(2026, 10, 10, 12, 0) }
  after { travel_back }

  def sign_in_manager
    create(:organization_role, :manager, user: admin, organization: org)
    post handle_signin_path, params: { email_address: admin.email_address, password: password }
    get manage_path
  end

  it "remembers which link brought the buyer, and the Links page says what each sold" do
    poster = production.short_links.create!(kind: "named", label: "Poster", organization: org, query: { "date" => "oct-17" })

    get "/t/#{poster.code}"
    expect(response).to redirect_to("/tickets/starsandgarters/#{production.public_key}?date=oct-17")
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { general.id => 2 } }
    order = TicketOrder.order(:id).last
    expect(order.short_link).to eq(poster)
    expect(order.utm).to eq("via" => poster.code)
    TicketOrderSettlement.settle!(order)

    sign_in_manager
    get manage_production_ticketing_links_path(production)
    expect(response.body).to include("cocoscout.com</span>/t/#{code}", "The production&#39;s link", "cocoscout.com</span>/t/#{poster.code}", "Poster",
                                     "Improvised Animorphs · oct-17", "$40.00")
    expect(response.body).to include(%(<td class="hidden sm:table-cell px-3 sm:px-4 py-3 text-right tabular-nums text-gray-900">2</td>))

    get manage_production_ticketing_path(production)
    expect(response.body).to include("2 links · 1 click")
  end

  it "makes a named link that opens a date with a code on, and archives it" do
    sign_in_manager
    production.ticket_discount_codes.create!(organization: org, code: "FRIENDS", kind: "percent", percent: 10)
    post manage_production_ticketing_links_path(production), params: { label: "Instagram bio", date: "oct-17", code: "friends" }
    link = production.short_links.named.last
    expect(link.label).to eq("Instagram bio")
    expect(link.query).to eq("date" => "oct-17", "code" => "FRIENDS")
    expect(link.created_by).to eq(admin)
    get "/t/#{link.code}"
    expect(response).to redirect_to("/tickets/starsandgarters/#{production.public_key}?code=FRIENDS&date=oct-17")

    post manage_production_ticketing_links_path(production), params: { label: "" }
    expect(flash[:alert]).to include("Give the link a name")

    delete manage_production_ticketing_link_path(production, link)
    expect(link.reload).to be_archived
    get "/t/#{link.code}"
    expect(response).to have_http_status(:not_found)
    get manage_production_ticketing_links_path(production)
    expect(response.body).not_to include("cocoscout.com</span>/t/#{link.code}")
  end

  it "swaps a code for a new one whenever the manager asks, opened or not; the old code keeps forwarding and isn't shown" do
    sign_in_manager
    canonical = ShortLink.canonical_for!(production)
    poster = production.short_links.create!(kind: "named", label: "Poster", organization: org)
    old_code = canonical.code
    old_poster = poster.code

    # Already opened: the manager testing it. The button is there all the same.
    get "/t/#{old_code}", headers: { "User-Agent" => "Mozilla/5.0" }
    expect(canonical.reload.clicks_count).to eq(1)
    get manage_production_ticketing_links_path(production)
    expect(response.body).to include("confirm-new-code-#{canonical.id}", "confirm-new-code-#{poster.id}", "Get a new code?",
                                     "The old code keeps forwarding")

    post manage_production_ticketing_link_new_code_path(production, canonical)
    expect(response).to redirect_to(manage_production_ticketing_links_path(production))
    expect(canonical.reload.code).not_to eq(old_code)
    expect(canonical).to be_canonical
    expect(flash[:notice]).to include("cocoscout.com/t/#{canonical.code}", "The old code still forwards to it")
    expect(flash[:notice]).not_to include(old_code)

    # The old code goes where the new one does, counts as the same link, and
    # is nowhere on the page.
    get "/t/#{old_code}", headers: { "User-Agent" => "Mozilla/5.0" }
    expect(response).to redirect_to("/tickets/starsandgarters/#{production.public_key}")
    expect(canonical.reload.clicks_count).to eq(2)
    get manage_production_ticketing_links_path(production)
    expect(response.body).to include("cocoscout.com</span>/t/#{canonical.code}", "confirm-new-code-#{canonical.id}")
    expect(response.body).not_to include(old_code)

    post manage_production_ticketing_link_new_code_path(production, poster)
    expect(poster.reload.code).not_to eq(old_poster)
    expect(flash[:notice]).to include("Poster is now cocoscout.com/t/#{poster.code}")
  end

  it "credits an order to the link when the buyer came in on its old code" do
    poster = production.short_links.create!(kind: "named", label: "Poster", organization: org)
    old_code = poster.code
    get "/t/#{old_code}"
    poster.regenerate_code!
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { general.id => 1 } }
    order = TicketOrder.order(:id).last
    expect(order.short_link).to eq(poster)
    expect(order.utm).to eq("via" => poster.reload.code)

    # Sold through, and it still swaps.
    TicketOrderSettlement.settle!(order)
    expect(poster.regenerate_code!).to be(true)
    expect(ShortLink.lookup(old_code)).to eq(poster)
  end

  it "doesn't swap another organization's code" do
    sign_in_manager
    other = create(:production, organization: create(:organization, :pro))
    theirs = ShortLink.canonical_for!(other)
    their_code = theirs.code
    post manage_production_ticketing_link_new_code_path(production, theirs)
    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.code).to eq(their_code)
  end

  it "doesn't attribute an order to another theater's link" do
    other = create(:organization, :pro)
    other_link = ShortLink.canonical_for!(TicketingProfile.for(other))
    get "/t/#{other_link.code}"
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { general.id => 1 } }
    expect(TicketOrder.order(:id).last.short_link).to be_nil
  end
end
