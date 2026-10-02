# frozen_string_literal: true

require "rails_helper"

# A show that moves after people bought: its page and the dashboard ask the
# theater to tell them, the email is read and edited first, and each buyer
# hears what they were told and what it is now. Nothing goes out by itself.
RSpec.describe "Telling buyers a show changed", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }
  let(:show) { listing.show }

  before do
    TicketingProfile.for(org).update!(enabled: true)
    show.update!(date_and_time: Time.zone.local(2026, 10, 16, 19, 30))
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
  end

  around { |example| travel_to(Time.zone.local(2026, 10, 2, 12)) { example.run } }

  def bought(name, email: "#{name.parameterize}@example.com")
    order = create(:ticket_order, ticket_listing: listing, status: "paid", paid_at: Time.current, money_path: "cocoscout",
                                  expires_at: nil, buyer_name: name, buyer_email: email)
    create(:ticket, ticket_order: order, ticket_tier: general)
    order
  end

  it "remembers what each buyer was told, and only asks once the show moves" do
    dana = bought("Dana Scully")
    expect(dana.told_starts_at).to eq(show.date_and_time)
    expect(TicketShowChange.pending?(listing)).to be(false)

    get manage_ticket_listing_path(listing)
    expect(response.body).not_to include("Tell buyers")

    show.update!(date_and_time: Time.zone.local(2026, 10, 17, 20, 0))
    bought("Fox Mulder") # bought after the change: already knows
    bought("Walk Up", email: nil)

    expect(TicketShowChange.orders(listing)).to contain_exactly(dana)
    get manage_ticket_listing_path(listing)
    expect(response.body).to include("1 buyer was told a different date, time or place", "Tell buyers")
    get manage_ticketing_path
    expect(response.body).to include("moved after people bought tickets")
  end

  it "previews the email for each buyer, then sends it in the background and marks them told" do
    dana = bought("Dana Scully")
    show.update!(date_and_time: Time.zone.local(2026, 10, 17, 20, 0))

    get manage_ticket_listing_change_path(listing)
    expect(response.body).to include("Who gets it", "dana-scully@example.com", "Email 1 buyer",
                                     "has a new date and time", "It was Friday, October 16 at 7:30 PM")
    expect(ActionMailer::Base.deliveries).to be_empty

    perform_enqueued_jobs do
      post manage_ticket_listing_change_path(listing),
           params: { subject: "{{show_title}}: new {{what_changed}}", body: "Hi {{first_name}},\n\nIt's now {{now}}. It was {{was}}." }
    end
    expect(response).to redirect_to(manage_ticket_listing_path(listing))

    mail = ActionMailer::Base.deliveries.sole
    html = (mail.html_part || mail).body.decoded
    expect(mail.to).to eq([ "dana-scully@example.com" ])
    expect(mail.subject).to eq("#{listing.display_title}: new date and time")
    expect(html).to include("Hi Dana,", "now Saturday, October 17 at 8:00 PM", "It was Friday, October 16 at 7:30 PM")
    expect(mail.attachments.map(&:filename)).to include("ticket-#{dana.tickets.sole.id}.png")
    expect(dana.reload.told_starts_at).to eq(show.reload.date_and_time)
    expect(TicketShowChange.pending?(listing)).to be(false)
  end

  it "names a new place, and can mark buyers told without an email" do
    dana = bought("Dana Scully")
    show.update!(location: create(:location, organization: org, name: "The Annex"))
    expect(TicketShowChange.variables(dana)[:what_changed]).to eq("place")
    expect(TicketShowChange.variables(dana)[:now]).to include("at The Annex")

    post manage_ticket_listing_change_told_path(listing)
    expect(flash[:notice]).to eq("Marked 1 buyer as told. No emails went out.")
    expect(TicketShowChange.pending?(listing)).to be(false)
    expect(TicketShowChangeJob).not_to have_been_enqueued
  end

  it "won't touch another theater's show" do
    other = create(:ticket_listing, organization: create(:organization, :pro))
    get manage_ticket_listing_change_path(other)
    expect(response).to have_http_status(:not_found)
    post manage_ticket_listing_change_told_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
