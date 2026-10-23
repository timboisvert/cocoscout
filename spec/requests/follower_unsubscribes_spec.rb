# frozen_string_literal: true

require "rails_helper"

# The unsubscribe link at the bottom of every email to followers.
RSpec.describe "Unsubscribing from an organization's emails", type: :request do
  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:main) { MailingList.main_for!(org) }
  let(:dan_list) { org.mailing_lists.create!(name: "Dan Feltey's shows") }
  let!(:follower) { Follower.for!(org, "maria@example.com").tap { |f| [ main, dan_list ].each { |l| l.mailing_list_memberships.create!(follower: f) } } }

  it "never unsubscribes on a plain fetch (link checkers), only on the page's post" do
    get follower_unsubscribe_path(token: follower.unsubscribe_token)
    expect(response.body).to include("Unsubscribe from Stars &amp; Garters?", "submit-on-load")
    expect(follower.reload).to be_subscribed

    post follower_unsubscribe_path(token: follower.unsubscribe_token)
    expect(follower.reload.status).to eq("unsubscribed")
    follow_redirect!
    expect(response.body).to include("You&#39;re unsubscribed", "Dan Feltey&#39;s shows", "Resubscribe")

    post follower_resubscribe_path(token: follower.unsubscribe_token)
    expect(follower.reload).to be_subscribed
    follow_redirect!
    expect(response.body).to include("You&#39;re back on the list")
  end

  it "answers a mail app's one-click unsubscribe plainly" do
    post follower_unsubscribe_path(token: follower.unsubscribe_token), params: { "List-Unsubscribe" => "One-Click" }
    expect(response).to have_http_status(:ok)
    expect(follower.reload.status).to eq("unsubscribed")
  end

  it "won't resubscribe an address that bounced" do
    follower.unsubscribe!
    EmailSuppression.suppress!(follower.email, reason: "bounced")
    post follower_resubscribe_path(token: follower.unsubscribe_token)
    expect(follower.reload.status).to eq("unsubscribed")
  end
end
