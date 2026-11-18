# frozen_string_literal: true

require "rails_helper"

# Emails to followers beyond the 500 a month Pro includes (Tim, 2026-11-17):
# blocks of 1,000 for $3, bought on the send screen when a send needs them.
# The month's 500 are used first and don't carry over; what a block paid for
# does. Each block goes on that month's bill.
RSpec.describe "Extra follower emails" do
  include ActiveJob::TestHelper

  let!(:owner) { create(:user) }
  let!(:organization) { create(:organization, :pro, owner: owner, name: "The Holly Problem") }
  let(:list) { MailingList.main_for!(organization) }
  let(:allowance) { FollowerEmailAllowance.new(organization) }

  def followers!(count, prefix: "f")
    now = Time.current
    rows = count.times.map do |i|
      { organization_id: organization.id, email: "#{prefix}#{i}@example.com", status: "subscribed", unsubscribe_token: SecureRandom.hex(12),
        created_at: now, updated_at: now }
    end
    ids = Follower.insert_all(rows, returning: %w[id]).rows.flatten
    MailingListMembership.insert_all(ids.map { |id| { mailing_list_id: list.id, follower_id: id, created_at: now, updated_at: now } })
  end

  def email!
    organization.follower_emails.create!(subject: "News", body: "<p>Hello</p>", status: "draft",
                                         targets: { "list_ids" => [ list.id ], "segment_ids" => [] }, created_by: owner)
  end

  # Marks an email's deliveries as sent, as the send job does.
  def delivered!(follower_email)
    follower_email.follower_email_deliveries.update_all(sent_at: Time.current, status: "sent")
  end

  it "sends within the month's 500 without buying anything" do
    followers!(120)
    sent = FollowerEmailSender.send!(email!, owner)

    expect(sent.reload).to have_attributes(recipient_count: 120, paid_emails_used: 0)
    expect(organization.follower_email_blocks).to be_empty
  end

  it "stops a send that needs more, saying what a block would cost, and never buys one nobody agreed to" do
    followers!(1_240)
    draft = email!

    expect(allowance.blocks_needed(1_240)).to eq(1)
    expect { FollowerEmailSender.send!(draft, owner) }.to raise_error(FollowerEmailSender::Error, /Add 1,000 more for \$3/)
    expect { FollowerEmailSender.send!(draft, owner, buy_blocks: 2) }.to raise_error(FollowerEmailSender::Error)
    expect(organization.follower_email_blocks).to be_empty
  end

  it "buys the block, uses the month's 500 first, and carries what's left of the block over" do
    followers!(1_240)
    sent = FollowerEmailSender.send!(email!, owner, buy_blocks: 1)
    delivered!(sent)

    expect(sent.reload.paid_emails_used).to eq(740)
    block = organization.follower_email_blocks.sole
    expect(block).to have_attributes(emails: 1_000, price_cents: 300, bought_by: owner, follower_email: sent)

    now = FollowerEmailAllowance.new(organization)
    expect(now).to have_attributes(used: 500, free_left: 0, paid_left: 260, left: 260)

    # Next month the 500 come back, and the 260 paid for are still there.
    travel_to(1.month.from_now.beginning_of_month + 2.days) do
      later = FollowerEmailAllowance.new(organization)
      expect(later).to have_attributes(used: 0, free_left: 500, paid_left: 260, left: 760)
      expect(later.paid_part(600)).to eq(100)
    end
  end

  it "freezes what was paid for while the organization isn't on Pro" do
    organization.follower_email_blocks.create!(bought_by: owner)
    expect(FollowerEmailAllowance.new(organization).paid_left).to eq(1_000)

    organization.update!(comped_indefinitely: false)
    expect(FollowerEmailAllowance.new(organization.reload).paid_left).to eq(0)
  end

  it "puts each block on the bill for the month it was bought" do
    month = Date.current.beginning_of_month
    organization.follower_email_blocks.create!(bought_by: owner)
    organization.follower_email_blocks.create!(bought_by: owner)

    expect(UsageRules.follower_email_blocks_cents(organization, month)).to eq(600)
    expect(UsageRules.follower_email_blocks_cents(organization, month.next_month)).to eq(0)
    expect(UsageRules.fees_cents(organization, month)).to be >= 600
    expect(UsageMonth.new(organization, month).follower_email_blocks_cents).to eq(600)
  end
end
