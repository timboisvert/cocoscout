# frozen_string_literal: true

require "rails_helper"

# Old /my links that still arrive from emails and the app: each lands
# somewhere real instead of an error or "not found".
RSpec.describe "Legacy /my links", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "sends an audition link's old /my/auditions/:token path to the audition page" do
    cycle = create(:audition_cycle, token: "AB3CD")
    get "/my/auditions/#{cycle.token}"
    expect(response).to redirect_to("/a/AB3CD")
  end

  it "sends an all-digit audition token there too" do
    create(:audition_cycle, token: "40917")
    get "/my/auditions/40917"
    expect(response).to redirect_to(submit_audition_request_path("40917"))
  end

  it "still says not found for an audition that isn't yours" do
    get "/my/auditions/999999"
    expect(response).to redirect_to(my_auditions_path)
    expect(flash[:alert]).to eq("Audition not found")
  end

  it "sends /my/profiles to the profile list under Account" do
    get my_profiles_path
    expect(response).to redirect_to(account_profiles_path)
  end
end
