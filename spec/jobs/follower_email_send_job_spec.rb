# frozen_string_literal: true

require "rails_helper"

# Sending an email to followers: one copy each, in the organization's look,
# with one-click unsubscribe, skipping anyone who left or bounced since.
RSpec.describe FollowerEmailSendJob do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let(:main) { MailingList.main_for!(org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters", support_email: "box@starsandgarters.example") } }
  let(:production) { create(:production, organization: org, name: "Laugh-Along, Live!") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 20)) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }

  def on_list(email, name = nil)
    Follower.for!(org, email, name: name).tap { |f| main.mailing_list_memberships.create!(follower: f) }
  end

  before { ActionMailer::Base.deliveries.clear }

  it "sends each follower their own copy and skips anyone who left after the send was confirmed" do
    maria = on_list("maria@example.com", "Maria Okafor")
    leaving = on_list("leaving@example.com", "Lee")
    on_list("gone@example.com").unsubscribe!
    email = org.follower_emails.create!(subject: "November", body: "<p>Hi {{first_name}}!</p>", show_ids: [ show.id ],
                                        targets: { "list_ids" => [ main.id ] }, created_by: owner)

    FollowerEmailSender.send!(email, owner)
    expect(email.follower_email_deliveries.pluck(:email)).to contain_exactly("maria@example.com", "leaving@example.com")
    leaving.unsubscribe!
    described_class.perform_now(email.id)

    expect(email.reload.status).to eq("sent")
    expect(email.follower_email_deliveries.find_by(follower: leaving).status).to eq("skipped")
    expect(email.follower_email_deliveries.find_by(follower: maria).status).to eq("sent")

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq([ "maria@example.com" ])
    expect(mail[:from].value).to eq(%("Stars & Garters via CocoScout" <info@cocoscout.com>))
    expect(mail.reply_to).to eq([ "box@starsandgarters.example" ])
    expect(mail["List-Unsubscribe"].value).to include(Rails.application.routes.url_helpers.follower_unsubscribe_path(token: maria.unsubscribe_token))
    expect(mail["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
    html = mail.html_part ? mail.html_part.body.decoded : mail.body.decoded
    expect(html).to include("Hi Maria!", "Laugh-Along, Live!", "Buy tickets", "utm_campaign=fe-#{email.id}",
                            "You're getting this because you asked to hear from Stars &amp; Garters.")
    expect(html).not_to include("cocoscout.png")
    expect(EmailLog.count).to eq(0)
  end

  it "refuses to send twice or to nobody" do
    email = org.follower_emails.create!(subject: "Hi", body: "<p>Hi</p>", targets: { "list_ids" => [ main.id ] })
    expect { FollowerEmailSender.send!(email, owner) }.to raise_error(FollowerEmailSender::Error, "Nobody on those lists can be emailed.")
    on_list("a@example.com")
    FollowerEmailSender.send!(email, owner)
    expect { FollowerEmailSender.send!(email.reload, owner) }.to raise_error(FollowerEmailSender::Error, "This email was already sent.")
  end

  it "counts against the month's allowance" do
    on_list("a@example.com")
    email = org.follower_emails.create!(subject: "Hi", body: "<p>Hi</p>", targets: { "list_ids" => [ main.id ] })
    FollowerEmailSender.send!(email, owner)
    described_class.perform_now(email.id)
    allowance = FollowerEmailAllowance.new(org)
    expect([ allowance.used, allowance.left ]).to eq([ 1, 499 ])
  end

  it "stops a send that would go past the month's 500" do
    stub_const("FollowerEmailAllowance::INCLUDED_PER_MONTH", 2)
    %w[a b c].each { |name| on_list("#{name}@example.com") }
    email = org.follower_emails.create!(subject: "Hi", body: "<p>Hi</p>", targets: { "list_ids" => [ main.id ] })
    expect { FollowerEmailSender.send!(email, owner) }.to raise_error(FollowerEmailSender::Error, /This would send 3 emails, and 2 are left this month/)
    expect(email.reload).to be_draft
  end

  # While follower email shares cocoscout.com's domain and Mailgun plan with
  # sign-in and ticket mail (Tim, 2026-10-28), every organization's sends
  # together stop at a monthly cap.
  it "stops a send that would take CocoScout past its monthly cap for every organization together" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FOLLOWERS_MONTHLY_CAP").and_return("4")
    other = create(:organization, :pro)
    other_main = MailingList.main_for!(other)
    Follower.for!(other, "x@example.com").tap { |f| other_main.mailing_list_memberships.create!(follower: f) }
    Follower.for!(other, "y@example.com").tap { |f| other_main.mailing_list_memberships.create!(follower: f) }
    FollowerEmailSender.send!(other.follower_emails.create!(subject: "Hi", body: "<p>Hi</p>", targets: { "list_ids" => [ other_main.id ] }), owner)

    %w[a b c].each { |name| on_list("#{name}@example.com") }
    email = org.follower_emails.create!(subject: "Hi", body: "<p>Hi</p>", targets: { "list_ids" => [ main.id ] })
    expect { FollowerEmailSender.send!(email, owner) }.to raise_error(FollowerEmailSender::Error, /CocoScout has sent all the emails to followers it can this month/)
    expect(email.reload).to be_draft
  end

  describe "switching it on in production" do
    before do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(ENV).to receive(:[]).and_call_original
    end

    it "stays off until it has its own domain or is switched on to share cocoscout.com's" do
      allow(ENV).to receive(:[]).with("FOLLOWERS_MAIL_DOMAIN").and_return(nil)
      allow(ENV).to receive(:[]).with("FOLLOWERS_SENDING").and_return(nil)
      expect(FollowerEmailSender.switched_on?).to be(false)

      allow(ENV).to receive(:[]).with("FOLLOWERS_SENDING").and_return("on")
      expect(FollowerEmailSender.switched_on?).to be(true)

      allow(ENV).to receive(:[]).with("FOLLOWERS_SENDING").and_return(nil)
      allow(ENV).to receive(:[]).with("FOLLOWERS_MAIL_DOMAIN").and_return("news.cocoscout.com")
      expect(FollowerEmailSender.switched_on?).to be(true)
    end
  end
end
