# frozen_string_literal: true

require "rails_helper"

# Producer-intent routing: the CTAs on /for-producers, /pricing, and
# /sketchfest declare why the visitor is signing up, and a brand-new signup
# with producer intent lands on the producer side instead of the talent
# dashboard. Intent rides the session (allowlisted, last-touch) and is
# consumed exactly once.
RSpec.describe "Signup intent routing", type: :request do
  let(:password) { "Password123!" }

  def sign_up(email)
    post handle_signup_path, params: { user: { email_address: email, password: password } }
  end

  describe "capturing intent" do
    it "captures producer intent from a CTA param" do
      get signup_path(intent: "producer")
      expect(session[:signup_intent]).to eq("producer")
    end

    it "ignores slugs outside the allowlist" do
      get signup_path(intent: "<script>admin</script>")
      expect(session[:signup_intent]).to be_nil
    end

    it "lets the most recent CTA win" do
      get signup_path(intent: "performer")
      get signup_path(intent: "producer")
      expect(session[:signup_intent]).to eq("producer")
    end

    it "treats landing on the SketchFest page as producer intent" do
      get sketchfest_path
      expect(session[:signup_intent]).to eq("producer")
    end

    it "carries the plan and interval from a Go Pro CTA" do
      get signup_path(intent: "producer", plan: "pro", interval: "month")
      expect(session[:signup_plan]).to eq("pro")
      expect(session[:signup_plan_interval]).to eq("month")
    end

    it "defaults a Go Pro click with a bogus interval to annual" do
      get signup_path(intent: "producer", plan: "pro", interval: "decade")
      expect(session[:signup_plan_interval]).to eq("year")
    end

    it "ignores a plan without producer intent" do
      get signup_path(plan: "pro")
      expect(session[:signup_plan]).to be_nil
    end
  end

  describe "landing after signup" do
    it "sends a producer-intent signup to the producer side" do
      get producers_path
      get signup_path(intent: "producer")
      sign_up("producer@example.com")

      expect(response).to redirect_to(manage_path)
    end

    it "sends an organic signup to the talent dashboard" do
      sign_up("organic@example.com")

      expect(response).to redirect_to(my_dashboard_path)
    end

    it "lets a stashed return path beat producer intent" do
      get signup_path(intent: "producer")
      get my_tasks_path # auth-walled — stashes the return path
      sign_up("interrupted@example.com")

      expect(response.headers["Location"]).to include(my_tasks_path)
    end

    it "consumes intent so it cannot leak into a later signin" do
      get signup_path(intent: "producer")
      sign_up("once@example.com")
      expect(session[:signup_intent]).to be_nil
      expect(session[:signup_plan]).to be_nil
    end

    it "routes a SketchFest signup to the producer side while keeping attribution" do
      get sketchfest_path
      sign_up("sketch@example.com")

      expect(response).to redirect_to(manage_path)
      expect(session[:referral_source]).to eq("sketchfest")
    end
  end
end
