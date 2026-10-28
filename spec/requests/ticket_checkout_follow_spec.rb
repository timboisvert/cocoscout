# frozen_string_literal: true

require "rails_helper"

# Checkout's mailing list boxes (Mailing lists, V1.1): the organization's main
# list, plus a producer's list on their shows; ticked by default; never at the
# door. After payment, the buyer joins what they ticked, and an email's link
# counts the sale on that email.
RSpec.describe "Joining mailing lists at ticket checkout", type: :request do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:dans) { create(:production, organization: org, name: "Comedy Hour", production_type: "third_party") }
  let(:in_house) { create(:production, organization: org, name: "Laugh-Along") }
  let!(:dan_list) { org.mailing_lists.create!(name: "Dan Feltey's shows").tap { |l| l.mailing_list_productions.create!(production: dans) } }
  let(:main) { MailingList.main_for!(org) }

  def listing_for(production)
    TicketListing.create!(show: create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 20)), status: "on_sale")
                 .tap { |l| l.ticket_tiers.create!(name: "General", price_cents: 0, quantity: 50) }
  end

  def boxes(order)
    get tickets_checkout_path(token: order.token)
    Nokogiri::HTML(response.body).css("[data-follow-boxes] label").map { |label| [ label.text.squish, label.at_css("input")["checked"].present? ] }
  end

  it "shows a producer's box and the main list's box on their show, ticked, and only the main one on an in-house show" do
    dan_order = TicketCheckout.start!(listing: (l = listing_for(dans)), quantities: { l.ticket_tiers.first.id.to_s => "1" })
    expect(boxes(dan_order)).to eq([ [ "Send me news about Dan Feltey's shows", true ], [ "Send me news from Stars & Garters", true ] ])

    house_order = TicketCheckout.start!(listing: (l2 = listing_for(in_house)), quantities: { l2.ticket_tiers.first.id.to_s => "1" })
    expect(boxes(house_order)).to eq([ [ "Send me news from Stars & Garters", true ] ])

    profile.update!(follow_boxes_ticked: false)
    expect(boxes(house_order).map(&:last)).to eq([ false ])
    profile.update!(follow_at_checkout: false)
    expect(boxes(house_order)).to eq([])
  end

  it "never asks at the door, once the door is open" do
    # Before the door opens a door sale is a presale and goes as an online one
    # (main 7472c4fe), so the show has to be tonight.
    listing = TicketListing.create!(show: create(:show, production: dans, date_and_time: 1.hour.from_now), status: "on_sale")
                           .tap { |l| l.ticket_tiers.create!(name: "General", price_cents: 0, quantity: 50) }
    expect(listing.door_ahead?).to be(false)
    order = TicketCheckout.start!(listing: listing, quantities: { listing.ticket_tiers.first.id.to_s => "1" }, channel: "door_card", at_door: true)
    expect(boxes(order)).to eq([])
  end

  it "keeps what they ticked, and after payment adds them to those lists with what they bought" do
    listing = listing_for(dans)
    order = TicketCheckout.start!(listing: listing, quantities: { listing.ticket_tiers.first.id.to_s => "1" })
    travel 5.seconds do
      post tickets_checkout_pay_path(token: order.token),
           params: { buyer_name: "Maria Okafor", buyer_email: "maria@example.com", follow_list_ids: [ "", dan_list.id.to_s ] }, as: :json
    end
    expect(order.reload.follow_list_ids).to eq([ dan_list.id ])
    expect(order.marketing_opt_in).to be(true)
    perform_enqueued_jobs(only: FollowTicketBuyerJob)

    maria = org.followers.find_by!(email: "maria@example.com")
    expect(maria.mailing_lists).to eq([ dan_list ])
    expect(maria.follower_sources.sole.attributes.slice("kind", "production_id", "ticket_order_id")).to eq("kind" => "checkout", "production_id" => dans.id, "ticket_order_id" => order.id)
    expect(maria.consented_at).to be_present
  end

  it "records a buyer who ticked nothing, but adds them to no list" do
    listing = listing_for(in_house)
    order = TicketCheckout.start!(listing: listing, quantities: { listing.ticket_tiers.first.id.to_s => "1" })
    travel 5.seconds do
      post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Sam", buyer_email: "sam@example.com", follow_list_ids: [ "" ] }, as: :json
    end
    perform_enqueued_jobs(only: FollowTicketBuyerJob)
    sam = org.followers.find_by!(email: "sam@example.com")
    expect(sam.mailing_lists).to be_empty
    expect(sam.consented_at).to be_nil
    expect(sam.follower_sources.count).to eq(1)
  end

  it "never puts back someone who unsubscribed" do
    gone = Follower.for!(org, "gone@example.com")
    gone.unsubscribe!
    listing = listing_for(in_house)
    order = TicketCheckout.start!(listing: listing, quantities: { listing.ticket_tiers.first.id.to_s => "1" })
    travel 5.seconds do
      post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Gone", buyer_email: "gone@example.com", follow_list_ids: [ main.id.to_s ] }, as: :json
    end
    perform_enqueued_jobs(only: FollowTicketBuyerJob)
    expect(gone.reload.status).to eq("unsubscribed")
    expect(gone.mailing_lists).to be_empty
  end

  it "counts a sale on the email whose link the buyer followed" do
    listing = listing_for(in_house)
    get tickets_event_path(org: "starsandgarters", event: listing.slug, utm_campaign: "fe-42")
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { listing.ticket_tiers.first.id => 1 } }
    expect(TicketOrder.last.utm).to include("campaign" => "fe-42")
  end
end
