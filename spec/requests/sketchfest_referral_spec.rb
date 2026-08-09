# frozen_string_literal: true

require "rails_helper"

# Attribution for the Chicago SketchFest sponsorship.
#
# The org is created several requests after the campaign link is clicked
# (marketing page -> signup -> /manage -> new organization), so the slug rides
# in the session. These specs pin the whole journey, because the value of the
# column is entirely in whether it survives that trip.
RSpec.describe "SketchFest referral attribution", type: :request do
  let(:password) { "Password123!" }

  describe "capturing the source" do
    it "stamps the session just from landing on the sponsor page" do
      get sketchfest_path
      expect(session[:referral_source]).to eq("sketchfest")
    end

    it "accepts ?ref= on signup for people who deep-link straight there" do
      get signup_path(ref: "sketchfest")
      expect(session[:referral_source]).to eq("sketchfest")
    end

    it "ignores slugs that aren't campaigns we run" do
      get signup_path(ref: "<script>whatever</script>")
      expect(session[:referral_source]).to be_nil
    end

    it "keeps the first touch when the visitor wanders the marketing site" do
      get sketchfest_path
      get producers_path(ref: "sketchfest")
      expect(session[:referral_source]).to eq("sketchfest")
    end

    it "leaves organic visitors unattributed" do
      get root_path
      expect(session[:referral_source]).to be_nil
    end
  end

  describe "the full journey to a created organization" do
    it "attributes an org created after a SketchFest signup" do
      get sketchfest_path
      post handle_signup_path, params: { user: { email_address: "team@example.com", password: password } }
      post manage_organizations_path, params: { organization: { name: "The Late Shift" } }

      expect(Organization.find_by(name: "The Late Shift").referral_source).to eq("sketchfest")
    end

    it "leaves referral_source nil for an organic signup" do
      post handle_signup_path, params: { user: { email_address: "organic@example.com", password: password } }
      post manage_organizations_path, params: { organization: { name: "Some Theater Co" } }

      expect(Organization.find_by(name: "Some Theater Co").referral_source).to be_nil
    end

    it "cannot be spoofed by posting the attribute directly" do
      post handle_signup_path, params: { user: { email_address: "sneaky@example.com", password: password } }
      post manage_organizations_path,
           params: { organization: { name: "Fake Referral Co", referral_source: "sketchfest" } }

      expect(Organization.find_by(name: "Fake Referral Co").referral_source).to be_nil
    end
  end

  describe "sketch-flavored copy" do
    it "swaps the signup panel for team language after the sponsor page" do
      get sketchfest_path
      get signup_path

      expect(response.body).to include("FREE FOR SKETCH TEAMS")
      expect(response.body).to include("Get your team organized")
    end

    it "leaves the default multi-persona signup panel alone otherwise" do
      get signup_path

      expect(response.body).to include("Create your CocoScout account")
      expect(response.body).not_to include("FREE FOR SKETCH TEAMS")
    end

    it "asks a sketch signup what their team is called, not their organization" do
      get sketchfest_path
      post handle_signup_path, params: { user: { email_address: "troupe@example.com", password: password } }
      get new_manage_organization_path

      expect(response.body).to include("Set up your team")
      expect(response.body).to include("e.g., The Late Shift")
      expect(response.body).not_to include("Organization Name")
    end

    it "keeps the generic organization form for everyone else" do
      post handle_signup_path, params: { user: { email_address: "generic@example.com", password: password } }
      get new_manage_organization_path

      expect(response.body).to include("Organization Name")
      expect(response.body).not_to include("Set up your team")
    end
  end
end
