# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notifications", type: :request do
  let(:user) { create(:user) }
  let(:org) { create(:organization, owner: user).tap { |o| create(:organization_role, :manager, user: user, organization: o) } }

  before { post handle_signin_path, params: { email_address: user.email_address, password: user.password } }

  def note(**attrs)
    user.notifications.create!({ category: "ticketing_sales", kind: "sale", title: "2 sold: Comedy Night, Fri", path: "/manage/ticketing", organization: org }.merge(attrs))
  end

  it "lists everything, read ones included, and filters to unread" do
    note(title: "Unread one")
    note(title: "Read one", read_at: 1.hour.ago)
    get notifications_path
    expect(response.body).to include("Unread one", "Read one")
    get notifications_path(filter: "unread")
    expect(response.body).to include("Unread one")
    expect(response.body).not_to include("Read one")
  end

  it "marks one read when it's opened, and goes to its page in its organization" do
    n = note
    get open_notification_path(n)
    expect(response).to redirect_to("/manage/ticketing")
    expect(n.reload).to be_read
    expect(session[:current_organization_id][user.id.to_s]).to eq(org.id)
  end

  it "never opens someone else's" do
    other = create(:user).notifications.create!(category: "pay", kind: "sent", title: "Theirs")
    get open_notification_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it "marks all read" do
    note
    note
    post read_notifications_path
    expect(user.notifications.unread.count).to eq(0)
  end

  it "asks before switching modes until told not to" do
    note
    get notifications_path
    expect(response.body).to include('data-notification-open-ask-value="true"')
    post notifications_switch_without_asking_path
    get notifications_path
    expect(response.body).to include('data-notification-open-ask-value="false"')
  end

  describe "settings" do
    it "saves push and email per group, and the old keys with them" do
      patch account_notifications_path, params: { push: { "messages" => "0", "ticketing_sales" => "0" }, email: { "casting" => "0" }, notifications: { "message_digest" => "1" } }
      user.reload
      expect(user.message_push?).to be(false)
      expect(user.notification_push?("ticketing_sales")).to be(false)
      expect(user.notification_enabled?(:vacancy_invitations)).to be(false)
    end

    it "shows a manager's ticketing plan, set by the organization" do
      TicketingProfile.for(org).update!(enabled: true, slug: "org-#{org.id}")
      get account_notifications_path
      expect(response.body).to include("Ticketing at #{org.name}", "The usual", "By plan")
    end
  end
end
