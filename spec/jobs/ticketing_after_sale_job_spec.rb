# frozen_string_literal: true

require "rails_helper"

# The "Each sale" email: every sale someone paid for, online or at the door
# (tap, scan to pay, cash); comps and passes used at the door stay quiet.
RSpec.describe TicketingAfterSaleJob do
  let(:org) { create(:organization, :pro) }
  let(:listing) { create(:ticket_listing, organization: org) }

  before do
    allow(TicketingNotifier).to receive(:notify)
    allow(TicketingMilestones).to receive(:check!)
  end

  def paid(channel, buyer_name: nil)
    create(:ticket_order, ticket_listing: listing, channel: channel, status: "paid", buyer_name: buyer_name, buyer_email: nil)
  end

  it "sends the sale email for online, website and paid door sales" do
    %w[online embed door_tap door_card door_cash].each do |channel|
      described_class.perform_now(paid(channel).id)
    end
    expect(TicketingNotifier).to have_received(:notify).with(org, :sale, anything).exactly(5).times
  end

  it "names a door buyer without a name as someone at the door" do
    described_class.perform_now(paid("door_cash").id)
    expect(TicketingNotifier).to have_received(:notify).with(org, :sale, hash_including(variables: hash_including(buyer_name: "Someone at the door")))
  end

  it "stays quiet for comps and passes used at the door, and for unpaid orders" do
    described_class.perform_now(paid("comp").id)
    described_class.perform_now(paid("door_pass").id)
    described_class.perform_now(create(:ticket_order, ticket_listing: listing, channel: "door_tap", status: "pending").id)
    expect(TicketingNotifier).not_to have_received(:notify)
  end
end
