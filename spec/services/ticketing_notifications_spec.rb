# frozen_string_literal: true

require "rails_helper"

# Ticketing's notices to the theater: who gets which (defaults until the
# theater chooses), any extra address, once-only notices, and each moment
# that sends one.
RSpec.describe "Ticketing notifications" do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, email_address: "owner@sg.example") }
  let(:manager) { create(:user, email_address: "manager@sg.example") }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner, stripe_account_id: "acct_sg", payouts_enabled: true) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 10) }
  let(:settings) { TicketingNotifications.new(org) }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    TicketingProfile.for(org).update!(enabled: true, slug: "starsandgarters")
    ActionMailer::Base.deliveries.clear
  end

  def mails_to(address)
    ActionMailer::Base.deliveries.select { |m| m.to.include?(address) }
  end

  def html(mail)
    (mail.html_part || mail).body.decoded
  end

  def sell(count, name: "Dana Scully")
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: name, buyer_email: "#{name.parameterize}@example.com")
    perform_enqueued_jobs { TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{order.id}") }
    order.reload
  end

  describe "who gets what" do
    it "sends the important ones to every manager until the theater chooses" do
      expect(settings.emails_for("daily_summary")).to contain_exactly("owner@sg.example", "manager@sg.example")
      expect(settings.emails_for("sale")).to be_empty
    end

    it "saves the theater's choices, extra addresses included, and drops anyone who's gone" do
      settings.save!(rules: { "sale" => [ "user:#{manager.id}", "email:box@sg.example", "user:999" ] },
                     emails: [ "Box@SG.example", "" ])
      fresh = TicketingNotifications.new(org)
      expect(fresh.extra_emails).to eq([ "box@sg.example" ])
      expect(fresh.emails_for("sale")).to contain_exactly("manager@sg.example", "box@sg.example")
      expect(fresh.emails_for("daily_summary")).to be_empty

      OrganizationRole.where(user: manager).destroy_all
      expect(TicketingNotifications.new(org).emails_for("sale")).to eq([ "box@sg.example" ])
      expect { settings.save!(rules: {}, emails: [ "not an email" ]) }.to raise_error(ArgumentError, /isn't an email/)
    end
  end

  it "emails each sale to whoever wants them, and nothing for comps" do
    settings.save!(rules: { "sale" => [ "email:box@sg.example" ] }, emails: [ "box@sg.example" ])
    sell(2)

    mail = mails_to("box@sg.example").sole
    expect(mail.subject).to eq("2 tickets sold: #{listing.display_title}, #{listing.show.date_and_time.strftime('%A, %B %-d')}")
    expect(html(mail)).to include("Dana Scully</strong> bought 2 General", "2 of 10 sold", "Change what you get")

    perform_enqueued_jobs { TicketComps.give!(listing, TicketComps.parse("Guest", listing: listing, default_tier: general), by: owner) }
    expect(mails_to("box@sg.example").size).to eq(1)
  end

  it "says a show is almost sold out, then sold out, once each" do
    sell(8)
    expect(mails_to("owner@sg.example").map(&:subject)).to include(a_string_starting_with("Only 2 left"))
    sell(2, name: "Fox Mulder")
    sell_attempt = mails_to("owner@sg.example").map(&:subject)
    expect(sell_attempt.grep(/\ASold out/).size).to eq(1)
    perform_enqueued_jobs { TicketingMilestones.check!(listing) }
    expect(mails_to("owner@sg.example").map(&:subject).grep(/\ASold out/).size).to eq(1)
  end

  it "sends the morning summary and the show-day note once" do
    listing.show.update!(date_and_time: Time.current.end_of_day - 2.hours)
    travel_to(1.day.ago) { sell(3) }

    2.times { perform_enqueued_jobs { TicketingDailyNoticesJob.perform_now } }
    subjects = mails_to("manager@sg.example").map(&:subject)
    expect(subjects.grep(/\ATicket sales for/).size).to eq(1)
    expect(subjects.grep(/\AToday:/).size).to eq(1)
    summary = mails_to("manager@sg.example").find { |m| m.subject.start_with?("Ticket sales for") }
    expect(html(summary)).to include("3 tickets sold", "Coming up")
  end

  it "tells the team about refunds, and about refunds that fail" do
    settings.save!(rules: { "refund_issued" => [ "user:#{owner.id}" ], "refund_problem" => [ "user:#{owner.id}" ] }, emails: [])
    order = sell(1)
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
    perform_enqueued_jobs { TicketOrderRefund.issue!(order, by: manager, reason: "Asked by email") }
    expect(mails_to("owner@sg.example").map(&:subject)).to include("Refund: $21.42 to Dana Scully")

    second = sell(1, name: "Fox Mulder")
    allow(Stripe::Refund).to receive(:create).and_raise(Stripe::StripeError.new("charge expired"))
    perform_enqueued_jobs do
      expect { TicketOrderRefund.issue!(second) }.to raise_error(TicketOrderRefund::Error)
    end
    problem = mails_to("owner@sg.example").find { |m| m.subject.start_with?("A refund didn't go through") }
    expect(html(problem)).to include("charge expired")
  end

  it "sends disputes to the theater and to CocoScout's superadmins" do
    order = sell(1)
    perform_enqueued_jobs { TicketDispute.opened!(order, order.total_cents) }
    expect(mails_to("owner@sg.example").map(&:subject)).to include("Disputed charge: Dana Scully, $21.42")
    expect(mails_to(User::SUPERADMIN_EMAILS.first)).to be_present
  end

  it "tells the team the money from last night is available" do
    listing.show.update!(date_and_time: 2.days.ago)
    perform_enqueued_jobs { TicketMoneyRelease.release!(listing) }
    expect(mails_to("owner@sg.example").map(&:subject)).to include(a_string_matching(/\AShow summary/))
  end

  it "reports withdrawals" do
    listing.show.update!(date_and_time: 5.days.from_now)
    travel_to(10.days.ago) { sell(2) }
    listing.update!(released_at: 3.days.ago)
    allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_1"))
    perform_enqueued_jobs { BalanceWithdrawalService.withdraw!(org, amount_cents: 1_000) }
    expect(mails_to("owner@sg.example").map(&:subject)).to include("$10.00 is on its way to your bank")
  end
end
