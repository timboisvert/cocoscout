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

RSpec.describe "A notification's own page", type: :request do
  let(:user) { create(:user) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: user.password } }

  it "opens a notice with no link on its own page, with its words" do
    n = user.notifications.create!(category: "courses", kind: "course_registration_confirmed", title: "You're registered", body: "<p>See you Tuesday.</p>")
    get open_notification_path(n)
    expect(response).to redirect_to(notification_path(n))
    follow_redirect!
    expect(response.body).to include("registered", "See you Tuesday.")
  end
end

RSpec.describe "Notifications in My Messages", type: :request do
  let(:user) { create(:user) }

  before { post handle_signin_path, params: { email_address: user.email_address, password: user.password } }

  it "has a Notifications row at the top, with the unread count, for the V1 apps that have no bell" do
    user.notifications.create!(category: "pay", kind: "sent", title: "Your pay is on its way")
    get my_messages_path
    row = Nokogiri::HTML(response.body).at_css("[data-notifications-row]")
    expect(row["href"]).to eq(notifications_path)
    expect(row.text).to include("Notifications", "1 unread")
  end

  it "asks from production mode too, but only for another organization's notice" do
    org = create(:organization, owner: user).tap { |o| create(:organization_role, :manager, user: user, organization: o) }
    other = create(:organization, name: "Moonlight Players", owner: user)
    create(:organization_role, :manager, user: user, organization: other)
    mine = Notifier.deliver_rendered(user: user, category: "casting", kind: "test", subject: "Ours", body: "<p><a href=\"/manage/shows\">Ours</a></p>", organization: org)
    theirs = Notifier.deliver_rendered(user: user, category: "casting", kind: "test", subject: "Theirs", body: "<p><a href=\"/manage/shows\">Theirs</a></p>", organization: other)
    personal = Notifier.deliver_rendered(user: user, category: "pay", kind: "test", subject: "Pay", body: "<p><a href=\"/my/payments\">Pay</a></p>", organization: org)

    post set_organization_path(id: org.id)
    get manage_path
    get notifications_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("a[href='#{open_notification_path(mine)}']")["data-switch"]).to eq("false")
    row = doc.at_css("a[href='#{open_notification_path(theirs)}']")
    expect(row["data-switch"]).to eq("true")
    expect(row["data-switch-title"]).to eq("Switch to Moonlight Players?")
    expect(doc.at_css("a[href='#{open_notification_path(personal)}']")["data-switch"]).to eq("false")

    get my_dashboard_path
    get notifications_path
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("a[href='#{open_notification_path(mine)}']")["data-switch"]).to eq("true")
    expect(doc.at_css("a[href='#{open_notification_path(mine)}']")["data-switch-title"]).to eq("Open in production mode?")
    expect(doc.at_css("a[href='#{open_notification_path(personal)}']")["data-switch"]).to eq("false")

    # Opening the other organization's notice switches there and says so, once.
    post set_organization_path(id: org.id)
    get manage_path
    get open_notification_path(theirs)
    expect(response).to redirect_to("/manage/shows")
    expect(session[:current_organization_id][user.id.to_s]).to eq(other.id)
    follow_redirect!
    expect(response.body).to include("Switched to <strong class=\"text-gray-900\">Moonlight Players</strong>")
    get manage_shows_path
    expect(response.body).not_to include("Switched to <strong")

    # A notice for an organization you can no longer open goes to its own words instead.
    OrganizationRole.where(user: user, organization: other).destroy_all
    other.update!(owner: create(:user))
    get open_notification_path(theirs)
    expect(response).to redirect_to(notification_path(theirs))
    expect(flash[:alert]).to include("Moonlight Players")
  end
end
