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
end
