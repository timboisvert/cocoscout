# frozen_string_literal: true

require "rails_helper"

# Segments pick followers on a list by what they bought (SegmentQuery).
RSpec.describe SegmentQuery do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:main) { MailingList.main_for!(org) }
  let(:in_house) { create(:production, organization: org, name: "Laugh-Along", production_type: "in_house") }
  let(:dans) { create(:production, organization: org, name: "Comedy Hour", production_type: "third_party") }
  let(:dan_list) { org.mailing_lists.create!(name: "Dan Feltey's shows").tap { |l| l.mailing_list_productions.create!(production: dans) } }

  def follower(email, *purchases)
    f = Follower.for!(org, email)
    main.mailing_list_memberships.create!(follower: f)
    purchases.each_with_index do |(production, at), i|
      order = create_order(production)
      f.follower_sources.create!(kind: "checkout", production: production, ticket_order: order, occurred_at: at || (i + 1).weeks.ago)
    end
    f
  end

  def create_order(production)
    show = create(:show, production: production, date_and_time: 1.week.ago)
    listing = TicketListing.create!(show: show, status: "on_sale")
    TicketOrder.create!(organization: org, ticket_listing: listing, status: "paid", channel: "online", money_path: "cocoscout", fee_mode: "buyer",
                        buyer_email: "x@example.com", buyer_name: "X")
  end

  def pick(rule) = described_class.new(org, rule).followers.pluck(:email).sort

  it "picks by what they bought, never bought, how often and how lately, and is limited to people on a list" do
    regular = follower("regular@example.com", [ in_house, 1.week.ago ], [ in_house, 3.weeks.ago ], [ dans, 5.weeks.ago ])
    dans_only = follower("dans@example.com", [ dans, 2.months.ago ])
    lapsed = follower("lapsed@example.com", [ in_house, 8.months.ago ])
    nobody = Follower.for!(org, "notonalist@example.com", consented: false)
    nobody.follower_sources.create!(kind: "checkout", production: in_house, occurred_at: 1.day.ago)

    expect(pick("conditions" => [ { "type" => "bought", "target" => "list:#{dan_list.id}" } ])).to eq(%w[dans@example.com regular@example.com])
    expect(pick("conditions" => [ { "type" => "bought", "target" => "list:#{dan_list.id}" }, { "type" => "never_bought", "target" => "type:in_house" } ]))
      .to eq(%w[dans@example.com])
    expect(pick("conditions" => [ { "type" => "times_at_least", "count" => 3 } ])).to eq(%w[regular@example.com])
    expect(pick("conditions" => [ { "type" => "last_bought", "when" => "before", "date" => 6.months.ago.to_date.to_s } ])).to eq(%w[lapsed@example.com])
    expect(pick("match" => "any", "conditions" => [ { "type" => "times_at_least", "count" => 3 }, { "type" => "last_bought", "when" => "before", "date" => 6.months.ago.to_date.to_s } ]))
      .to eq(%w[lapsed@example.com regular@example.com])
    expect(pick("conditions" => [ { "type" => "bought", "target" => "any" } ])).not_to include("notonalist@example.com")
    expect([ regular, dans_only, lapsed ].size).to eq(3)
  end

  it "says what a segment picks" do
    segment = org.segments.new(name: "Dan's crowd", rule: { "conditions" => [ { "type" => "bought", "target" => "list:#{dan_list.id}" },
                                                                                { "type" => "never_bought", "target" => "type:in_house" } ] })
    expect(segment.summary).to eq("Bought tickets to any of Dan Feltey's shows, and Never bought tickets to an in-house production")
  end
end
