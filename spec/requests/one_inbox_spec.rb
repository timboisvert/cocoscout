# frozen_string_literal: true

require "rails_helper"

# The one Messages inbox (V1.1 plan §0a; Tim, 2026-10-21): someone who
# performs for one organization and runs another sees every thread in one
# list, in either mode, each under its hat; the "For" chips keep one; opening
# a thread switches organization (and mode) when it lives somewhere else.
RSpec.describe "The one Messages inbox", type: :request do
  let(:password) { "Password123!" }
  let(:sam) { create(:user, password: password) }
  let!(:sam_person) { create(:person, name: "Sam Both", user: sam).tap { |p| sam.update!(default_person: p) } }

  # Starlight: Sam performs there (no role).
  let(:starlight_owner) { create(:user).tap { |u| u.update!(default_person: create(:person, name: "Olive Owner", user: u)) } }
  let!(:starlight) { create(:organization, name: "Starlight Theater", owner: starlight_owner) }
  let!(:starlight_role) { create(:organization_role, :manager, user: starlight_owner, organization: starlight) }
  let!(:starlight_show) { create(:production, organization: starlight, name: "Cabaret Nights") }

  # Moonlight: Sam manages it.
  let!(:moonlight) { create(:organization, name: "Moonlight Players", owner: sam) }
  let!(:moonlight_role) { create(:organization_role, :manager, user: sam, organization: moonlight) }
  let!(:moonlight_show) { create(:production, organization: moonlight, name: "Open Mic") }
  let(:moonlight_performer) { create(:person, name: "Pat Performer", user: create(:user)) }

  let!(:performer_thread) do
    Current.organization = starlight
    MessageService.create_message(sender: starlight_owner, recipients: [ sam_person ], subject: "Your call time Friday", body: "7pm please",
                                  message_type: :direct, visibility: :personal, production: starlight_show)
  end
  let!(:production_thread) do
    Current.organization = moonlight
    MessageService.create_message(sender: sam, recipients: [ moonlight_performer ], subject: "Open Mic lineup", body: "You're on third",
                                  message_type: :direct, visibility: :personal, production: moonlight_show)
  end

  before do
    performer_thread && production_thread
    Current.organization = nil
    post handle_signin_path, params: { email_address: sam.email_address, password: password }
  end

  def rows(body)
    Nokogiri::HTML(body).css("a[data-message-id]")
  end

  it "lists both hats on My, the production thread with its organization's pill" do
    get messages_path
    expect(response).to have_http_status(:ok)
    found = rows(response.body)
    expect(found.map { |r| r["data-message-id"].to_i }).to contain_exactly(performer_thread.id, production_thread.id)
    performer_row = found.find { |r| r["data-message-id"].to_i == performer_thread.id }
    production_row = found.find { |r| r["data-message-id"].to_i == production_thread.id }
    expect(performer_row.at_css("[data-inbox-pill]")).to be_nil
    expect(performer_row["data-switch"]).to be_nil
    expect(production_row.at_css("[data-inbox-pill]").text.squish).to eq("Moonlight Players")
    expect(production_row["data-switch"]).to eq("true")
    expect(production_row["data-switch-title"]).to eq("Open in production mode?")
    expect(production_row["href"]).to eq(open_my_message_path(production_thread))
    expect(response.body).to include("As a performer", "Moonlight Players")
    expect(response.body).not_to include("Starlight Theater</a>")
  end

  it "shows the same list in production mode, the current organization's pill pink and no switch" do
    get manage_path
    get messages_path
    expect(response).to have_http_status(:ok)
    found = rows(response.body)
    expect(found.map { |r| r["data-message-id"].to_i }).to contain_exactly(performer_thread.id, production_thread.id)
    production_row = found.find { |r| r["data-message-id"].to_i == production_thread.id }
    expect(production_row.at_css("[data-inbox-pill]")["class"]).to include("bg-pink-50")
    expect(production_row["data-switch"]).to be_nil
    expect(response.body).to include(open_my_message_path(performer_thread))
  end

  it "keeps one hat with the For chips" do
    get messages_path(hat: "performer")
    expect(rows(response.body).map { |r| r["data-message-id"].to_i }).to eq([ performer_thread.id ])
    get messages_path(hat: "org:#{moonlight.id}")
    expect(rows(response.body).map { |r| r["data-message-id"].to_i }).to eq([ production_thread.id ])
    get messages_path(hat: "org:#{starlight.id}") # not one Sam runs: everything
    expect(rows(response.body).size).to eq(2)
  end

  it "opens a performer thread on My and a production thread in that organization's production mode" do
    get open_my_message_path(performer_thread)
    expect(response).to redirect_to(my_message_path(performer_thread))

    get open_my_message_path(production_thread)
    expect(response).to redirect_to(manage_message_path(production_thread))
    expect(session[:current_organization_id][sam.id.to_s]).to eq(moonlight.id)
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Open Mic lineup")
    # Coming from My: the page says where you landed, once.
    expect(response.body).to include("Switched to <strong class=\"text-gray-900\">Moonlight Players</strong>")
    get manage_message_path(production_thread)
    expect(response.body).not_to include("Switched to <strong")
    # Already in that organization's production mode: nothing to say.
    get open_my_message_path(production_thread)
    follow_redirect!
    expect(response.body).not_to include("Switched to <strong")
  end

  it "reads a performer thread right there in production mode, replying as Sam, not as a team" do
    get manage_path
    get open_my_message_path(performer_thread)
    expect(response).to redirect_to(manage_message_path(performer_thread))
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your call time Friday")
    expect(response.body).not_to include('data-value="production_team"')
    expect(response.body).not_to include('name="sender_identity"') # no identity choice: a reply is Sam's
    # Replying "as the production team" from there is refused quietly: the reply is personal.
    post reply_manage_message_path(performer_thread), params: { body: "On my way", sender_identity: "production_team" }
    expect(Message.where(parent_message: performer_thread).last.visibility).to eq("personal")
    # And the remembered mode is still production mode.
    get start_path, headers: { "User-Agent" => "CocoScout/1.1 (12; nav 2) Mozilla/5.0 (iPhone) Hotwire Native iOS; Turbo Native iOS" }
    expect(response).to redirect_to(manage_path)
  end

  it "sends pushes and a notification's Reply through the opener" do
    expect(Rails.root.join("app/services/push_notification_service.rb").read).to include("open_my_message_path(root)")
    expect(Rails.root.join("app/services/message_service.rb").read).to include("reply_path: Rails.application.routes.url_helpers.open_my_message_path(root_message)")
  end

  it "won't open a thread Sam isn't in" do
    stranger = create(:person, user: create(:user))
    Current.organization = starlight
    other = MessageService.create_message(sender: starlight_owner, recipients: [ stranger ], subject: "Private", body: "x", message_type: :direct, visibility: :personal)
    Current.organization = nil
    get open_my_message_path(other)
    expect(response).to redirect_to(messages_path)
  end

  it "counts both hats on the mail icon in either mode" do
    expect(sam.unread_message_count).to eq(1) # the performer thread; Sam sent the other
    get my_dashboard_path
    icon = Nokogiri::HTML(response.body).at_css("[data-universal-icon='messages']")
    expect(icon["aria-label"]).to eq("Messages, 1 unread")
    expect(icon["href"]).to eq(messages_path)
    get manage_path
    icon = Nokogiri::HTML(response.body).at_css("[data-universal-icon='messages']")
    expect(icon["aria-label"]).to eq("Messages, 1 unread")
    expect(icon["href"]).to eq(messages_path)
  end
end
