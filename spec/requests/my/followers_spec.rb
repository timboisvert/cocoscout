# frozen_string_literal: true

require "rails_helper"

# My Followers (Mailing lists, V1.1): a producer sees every follower the
# organizations share with them, one row per email, with where each came from;
# adds people; exports. Never sends.
RSpec.describe "My Followers", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:dan_user) { create(:user, password: password) }
  let!(:dan) { create(:person, user: dan_user, name: "Dan Feltey", email: dan_user.email_address).tap { |p| dan_user.update!(default_person: p) } }
  let(:stars) { create(:organization, :pro, name: "Stars & Garters") }
  let(:babs) { create(:organization, :pro, name: "Babs") }
  let(:stars_production) { create(:production, organization: stars, name: "Comedy Hour", production_type: "third_party") }
  let!(:stars_list) { stars.mailing_lists.create!(name: "Dan Feltey's shows").tap { |l| l.mailing_list_productions.create!(production: stars_production) } }
  let!(:babs_list) { babs.mailing_lists.create!(name: "Dan Feltey Live") }

  def on(list, email, name: nil, source: nil)
    Follower.for!(list.organization, email, name: name).tap do |f|
      list.mailing_list_memberships.create!(follower: f)
      f.follower_sources.create!(source.merge(occurred_at: 3.days.ago)) if source
    end
  end

  def sign_in
    post handle_signin_path, params: { email_address: dan_user.email_address, password: password }
  end

  it "is a 404 and no nav item without a share" do
    sign_in
    get my_followers_path
    expect(response).to have_http_status(:not_found)
    get my_dashboard_path
    expect(response.body).not_to include(">My Followers<")
  end

  context "shared from two organizations" do
    before do
      stars_list.mailing_list_shares.create!(person: dan)
      babs_list.mailing_list_shares.create!(person: dan)
      on(stars_list, "maria@example.com", name: "Maria Okafor", source: { kind: "checkout", production: stars_production })
      on(babs_list, "maria@example.com", name: "Maria Okafor", source: { kind: "manual", mailing_list: babs_list })
      on(stars_list, "gone@example.com", name: "Gone Person").unsubscribe!
      # Someone on another Stars list Dan wasn't given.
      on(stars.mailing_lists.create!(name: "Private"), "private@example.com")
      sign_in
    end

    it "shows one row per email with both organizations, in the My nav between My Payments and My Documents" do
      get my_followers_path
      expect(response).to have_http_status(:ok)
      rows = Nokogiri::HTML(response.body).css("[data-my-followers] > div")
      expect(rows.size).to eq(1)
      expect(rows.first.text.squish).to include("Maria Okafor", "Stars & Garters", "Tickets · Comedy Hour", "Babs", "Added by hand")
      expect(response.body).not_to include("private@example.com")

      labels = Nokogiri::HTML(response.body).css("nav a, aside a").map { |a| a.text.squish }
      expect(labels.index("My Payments")).to be < labels.index("My Followers")
      expect(labels.index("My Followers")).to be < labels.index("My Documents")

      get my_followers_path(show: "unsubscribed")
      expect(response.body).to include("Gone Person", "Not in exports")
    end

    it "adds a follower to a list it picks, marked as added by them" do
      post my_followers_path, params: { name: "Rosa", email: "rosa@example.com", mailing_list_id: stars_list.id, permission: "1" }
      rosa = stars.followers.find_by!(email: "rosa@example.com")
      expect(stars_list.followers).to include(rosa)
      expect(rosa.follower_sources.sole.attributes.slice("kind", "added_by_person_id")).to eq("kind" => "added_by_share", "added_by_person_id" => dan.id)

      post my_followers_path, params: { name: "X", email: "x@example.com", mailing_list_id: stars.mailing_lists.find_by(name: "Private").id, permission: "1" }
      expect(flash[:alert]).to eq("Pick a list to add them to.")
    end

    it "exports everyone still following, by email" do
      ActionMailer::Base.deliveries.clear
      post my_followers_export_path
      perform_enqueued_jobs(only: FollowersExportJob)
      mail = ActionMailer::Base.deliveries.last
      csv = mail.attachments.find { |a| a.filename.end_with?(".csv") }.decoded
      expect(csv).to include("maria@example.com", "Stars & Garters; Babs")
      expect(csv).not_to include("gone@example.com", "private@example.com")
    end

    it "loses access when the shares are removed" do
      MailingListShare.where(person: dan).destroy_all
      get my_followers_path
      expect(response).to have_http_status(:not_found)
    end
  end
end
