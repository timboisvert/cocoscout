# frozen_string_literal: true

require "rails_helper"

# Mailing lists (Pro, V1.1; Tim 2026-10-23): lists, adding people, sharing,
# where a list collects, segments, emails and settings, for an organization's
# managers on Pro.
RSpec.describe "Mailing lists", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_person) { create(:person, user: owner, name: "Tim Owner").tap { |p| owner.update!(default_person: p) } }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:main) { MailingList.main_for!(org) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
    post set_organization_path(id: org.id)
  end

  before { sign_in(owner) }

  it "has a home with the main list, segments and emails, and Mailing lists in the Pro nav after Ticketing" do
    get manage_mailing_lists_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("Mailing lists", "Stars &amp; Garters", "Main list", "No segments yet", "No emails yet")
    labels = Nokogiri::HTML(body).css("nav a, aside a").map { |a| a.text.squish }
    expect(labels).to include("Mailing lists")
    expect(labels.index("Ticketing")).to be < labels.index("Mailing lists")
    expect(labels.index("Mailing lists")).to be < labels.index("Staffing")
  end

  it "makes a list, adds one person, pastes many (checking first), and takes someone off" do
    post manage_mailing_lists_path, params: { mailing_list: { name: "Dan Feltey's shows" } }
    list = org.mailing_lists.find_by!(name: "Dan Feltey's shows")
    expect(response).to redirect_to(manage_mailing_list_path(list))

    post manage_mailing_list_followers_path(list), params: { name: "Rosa Delgado", email: "Rosa@Example.com" }
    rosa = org.followers.find_by!(email: "rosa@example.com")
    expect(list.followers).to include(rosa)
    expect(rosa.follower_sources.last.kind).to eq("manual")

    gone = Follower.for!(org, "gone@example.com", name: "Gone")
    gone.unsubscribe!
    EmailSuppression.suppress!("bounce@example.com", reason: "bounced")
    paste = "Rosa Delgado, rosa@example.com\nnew@example.com\nBen <gone@example.com>\nbounce@example.com\nnot an email"
    post manage_check_mailing_list_followers_path(list), params: { text: paste }
    expect(response.body).to include('data-follower-paste-addable="1"', "Already on it", "Unsubscribed: won&#39;t be added", "Bounced before")

    post manage_mailing_list_followers_path(list), params: { text: paste }
    expect(flash[:alert]).to include("asked to hear from you")
    post manage_mailing_list_followers_path(list), params: { text: paste, permission: "1" }
    expect(flash[:notice]).to eq("Added 1 person to Dan Feltey's shows.")
    expect(list.followers.reload.pluck(:email)).to contain_exactly("rosa@example.com", "new@example.com")

    delete manage_mailing_list_follower_path(list, follower_id: rosa.id)
    expect(list.followers.reload.pluck(:email)).to eq([ "new@example.com" ])
  end

  it "shows a list with where it collects, who can see it, and the standard Actions box" do
    list = org.mailing_lists.create!(name: "Dan Feltey's shows")
    production = create(:production, organization: org, name: "Comedy Hour", production_type: "third_party")
    patch manage_mailing_list_productions_path(list), params: { production_ids: [ production.id ] }
    expect(list.productions.reload).to eq([ production ])

    get manage_mailing_list_path(list)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("[data-collects-from]").text).to include("Comedy Hour", "Contract", "Send me news about Dan Feltey's shows")
    expect(doc.at_css("[data-who-can-see]")).to be_nil # lists aren't shared outside the organization
    expect(response.body).not_to include("Change who can see it", "My Followers")
    expect(response.body).to include("Change where it collects", "Export", "Rename", "Archive this list")
    # The standard sub-page header: the breadcrumb line, not a big title.
    expect(response.body).to include(manage_mailing_lists_path, "Write an email")
  end

  it "adds someone from Contacts to a list" do
    person = create(:person, name: "Priya Shah", email: "priya@example.com")
    org.people << person
    get manage_contacts_person_path(person)
    expect(response.body).to include("Add to a mailing list")
    post manage_mailing_lists_add_person_path, params: { person_id: person.id, mailing_list_id: main.id }
    follower = org.followers.find_by!(email: "priya@example.com")
    expect(main.followers).to include(follower)
    expect(follower.person).to eq(person)
    expect(follower.follower_sources.sole.kind).to eq("contacts")
  end

  it "archives a group list but never the main one" do
    list = org.mailing_lists.create!(name: "Old show")
    post manage_archive_mailing_list_path(list)
    expect(list.reload).to be_archived
    post manage_archive_mailing_list_path(main)
    expect(main.reload).not_to be_archived
  end

  it "keeps one organization's lists from another" do
    other = create(:organization, :pro, name: "Babs")
    their_list = MailingList.main_for!(other)
    get manage_mailing_list_path(their_list)
    expect(response).to have_http_status(:not_found)
  end

  it "saves the email look and the checkout boxes" do
    patch manage_mailing_list_settings_look_path, params: { organization: { email_accent_color: "#1e3a8a", email_footer_line: "Comedy since 2019",
                                                                            email_mailing_address: "1 Main St, Chicago, IL 60601" } }
    expect(org.reload.email_accent).to eq("#1e3a8a")
    expect(org.email_postal_address).to eq("1 Main St, Chicago, IL 60601")

    patch manage_mailing_list_settings_checkout_path, params: { ticketing_profile: { follow_boxes_ticked: "0", follow_main_words: "Keep me posted" } }
    profile = TicketingProfile.for(org)
    expect(profile.follow_boxes_ticked).to be(false)
    expect(main.box_words).to eq("Keep me posted")

    %w[look checkout allowance].each do |section|
      get manage_mailing_list_settings_path(section: section)
      expect(response).to have_http_status(:ok)
    end
  end

  it "makes a segment and counts it live" do
    get manage_new_segment_path
    expect(response).to have_http_status(:ok)
    post manage_segments_path, params: { segment: { name: "Regulars" }, match: "all",
                                         conditions: { "0" => { type: "times_at_least", count: "3" } } }
    segment = org.segments.find_by!(name: "Regulars")
    expect(segment.rule).to eq("match" => "all", "conditions" => [ { "type" => "times_at_least", "count" => "3" } ])
    get manage_segment_path(segment)
    expect(response).to have_http_status(:ok)

    main.mailing_list_memberships.create!(follower: Follower.for!(org, "a@example.com"))
    get manage_segments_count_path, params: { match: "all", conditions: { "0" => { type: "on_list", list_id: main.id } } }
    expect(response.parsed_body["count"]).to eq(1)
  end

  describe "emails" do
    let!(:maria) { Follower.for!(org, "maria@example.com", name: "Maria Okafor").tap { |f| main.mailing_list_memberships.create!(follower: f) } }
    let!(:gone) { Follower.for!(org, "gone@example.com", name: "Gone").tap { |f| main.mailing_list_memberships.create!(follower: f); f.unsubscribe! } }

    it "writes a draft to the main list, reviews it with who gets it, sends it, and shows what it did" do
      get manage_new_follower_email_path
      email = org.follower_emails.last
      expect(response).to redirect_to(manage_edit_follower_email_path(email))
      expect(email.list_ids).to eq([ main.id ])

      patch manage_follower_email_path(email), params: { follower_email: { subject: "November at Stars & Garters", body: "<p>Hi {{first_name}}, come see us.</p>" },
                                                         list_ids: [ main.id ], review: "1" }
      expect(response).to redirect_to(manage_edit_follower_email_path(email, review: 1))
      get manage_edit_follower_email_path(email, review: 1)
      expect(response.body).to include("Send this email?", "Stars &amp; Garters list", "Left out: unsubscribed or bounced", "Send to 1 person")

      get manage_follower_email_preview_path(email)
      expect(response.body).to include("Hi Tim, come see us.", "Unsubscribe")

      post manage_follower_email_deliver_path(email)
      expect(email.reload.status).to eq("sending")
      expect(email.follower_email_deliveries.pluck(:email)).to eq([ "maria@example.com" ])
      perform_enqueued_jobs(only: FollowerEmailSendJob)
      expect(email.reload.status).to eq("sent")

      get manage_follower_email_path(email)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sales from this email", "Who it reached")
    end

    it "announces a show with a starter draft and the show's block" do
      show = create(:show, production: create(:production, organization: org, name: "Laugh-Along, Live!"), date_and_time: 5.days.from_now.change(hour: 20))
      get manage_new_follower_email_path(show_id: show.id)
      email = org.follower_emails.last
      expect(email.subject).to start_with("Laugh-Along, Live!:")
      expect(email.body.to_s).to include("{{first_name}}")
      expect(email.show_ids).to eq([ show.id ])
    end

    it "sends a test to the manager" do
      email = org.follower_emails.create!(subject: "Hello", body: "<p>Hi</p>", targets: { "list_ids" => [ main.id ] }, created_by: owner)
      expect { post manage_follower_email_test_path(email) }.to have_enqueued_mail(FollowerMailer, :test_email)
    end
  end

  describe "who can't" do
    it "puts Producer-plan organizations behind the upgrade" do
      org.update!(comped_indefinitely: false)
      get manage_mailing_lists_path
      expect(response).not_to have_http_status(:ok)
    end

    it "keeps a production team member out" do
      member = create(:user, password: password)
      create(:organization_role, user: member, organization: org, company_role: "member")
      delete session_path rescue nil
      sign_in(member)
      get manage_mailing_lists_path
      expect(response.body).not_to include("Change who can see it")
      expect(response).not_to have_http_status(:ok)
    end
  end
end
