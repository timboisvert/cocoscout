# frozen_string_literal: true

require "rails_helper"

# The combined first-run flow for brand-new producers: genre -> name -> plan,
# creating the Organization and its first Production together from one name.
RSpec.describe "Producer setup", type: :request do
  let(:password) { "Password123!" }

  # The flow keeps step state in Rails.cache (like the production wizard), and
  # the test env cache is a null store — give these examples a real one.
  let(:memory_cache) { ActiveSupport::Cache::MemoryStore.new }
  before { allow(Rails).to receive(:cache).and_return(memory_cache) }

  def sign_up(email = "producer@example.com")
    post handle_signup_path, params: { user: { email_address: email, password: password } }
  end

  def complete_setup(genre: "sketch", name: "The Late Shift", plan: "free", interval: nil)
    post manage_producer_setup_save_genre_path, params: { genre: genre }
    post manage_producer_setup_save_name_path, params: { name: name }
    post manage_producer_setup_complete_path, params: { plan: plan, interval: interval }.compact
  end

  describe "the happy path" do
    it "creates the org and production together and lands on the manage home" do
      sign_up
      complete_setup

      org = Organization.find_by(name: "The Late Shift")
      expect(org).to be_present
      expect(org.owner.email_address).to eq("producer@example.com")

      production = org.productions.find_by(name: "The Late Shift")
      expect(production).to be_present
      expect(production.genre).to eq("sketch")
      # Genre never seeds roles — the user defines their own.
      expect(production.roles).to be_empty

      expect(response).to redirect_to(manage_path)
    end

    it "activates the what's-next panel on the manage home" do
      sign_up
      complete_setup

      expect(User.find_by(email_address: "producer@example.com").guide_active?(:production_next_steps)).to be(true)

      get manage_path
      expect(response.body).to include("Here&#39;s what to do next")
    end

    it "hides the what's-next panel once dismissed, with a way back" do
      sign_up
      complete_setup

      post manage_guide_dismiss_path("production_next_steps")
      get manage_path
      expect(response.body).not_to include("data-intro-guide=\"production_next_steps\"")
      expect(response.body).to include("Show guide")

      post manage_guide_restore_path("production_next_steps")
      get manage_path
      expect(response.body).to include("data-intro-guide=\"production_next_steps\"")
    end

    it "makes the creator a manager and a member of the org" do
      sign_up
      complete_setup

      org = Organization.find_by(name: "The Late Shift")
      user = User.find_by(email_address: "producer@example.com")
      expect(org.organization_roles.find_by(user: user).company_role).to eq("manager")
      expect(org.people).to include(user.person)
    end

    it "dismisses the Start Producing welcome" do
      sign_up
      complete_setup

      expect(User.find_by(email_address: "producer@example.com").welcomed_production_at).to be_present
    end
  end

  describe "plan choice" do
    it "always shows both Pro intervals" do
      sign_up
      post manage_producer_setup_save_genre_path, params: { genre: "improv" }
      post manage_producer_setup_save_name_path, params: { name: "Fourth Wall" }
      get manage_producer_setup_plan_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Annual ($200/yr)")
      expect(response.body).to include("Monthly ($20/mo)")
      expect(response.body).to include("free forever")
    end

    it "sends a Pro choice into checkout with the chosen interval" do
      sign_up
      complete_setup(plan: "pro", interval: "month")

      expect(response).to redirect_to(manage_billing_path(upgrade: "month"))
      # The org exists on the free tier until Stripe confirms.
      expect(Organization.find_by(name: "The Late Shift").subscription_tier).to eq("free")
      # The what's-next panel is armed even though checkout comes first.
      expect(User.find_by(email_address: "producer@example.com").guide_active?(:production_next_steps)).to be(true)
    end

    it "defaults a bogus interval to annual" do
      sign_up
      complete_setup(plan: "pro", interval: "decade")

      expect(response).to redirect_to(manage_billing_path(upgrade: "year"))
    end
  end

  describe "attribution and flavoring" do
    it "stamps referral_source on the created org" do
      get sketchfest_path
      sign_up("sketch@example.com")
      complete_setup

      expect(Organization.find_by(name: "The Late Shift").referral_source).to eq("sketchfest")
    end

    it "preselects the sketch genre for SketchFest arrivals" do
      get sketchfest_path
      sign_up("sketch@example.com")
      get manage_producer_setup_path

      expect(response.body).to match(/value="sketch"[^>]*checked/)
    end

    it "asks what the team is called for a sketch genre" do
      sign_up
      post manage_producer_setup_save_genre_path, params: { genre: "sketch" }
      get manage_producer_setup_name_path

      expect(response.body).to include("What's your team called?")
    end
  end

  describe "guards" do
    it "rejects a genre outside the catalog" do
      sign_up
      post manage_producer_setup_save_genre_path, params: { genre: "polka" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Organization.count).to eq(0)
    end

    it "creates nothing when a step is skipped" do
      sign_up
      post manage_producer_setup_complete_path, params: { plan: "free" }

      expect(response).to redirect_to(manage_producer_setup_path)
      expect(Organization.count).to eq(0)
      expect(Production.count).to eq(0)
    end

    it "bounces users who already have an organization" do
      sign_up
      complete_setup
      get manage_producer_setup_path

      expect(response).to redirect_to(manage_path)
    end

    it "requires authentication" do
      get manage_producer_setup_path
      expect(response).to redirect_to(signin_path)
    end
  end

  describe "deep-link intent" do
    it "honors a stashed manage deep link after setup" do
      sign_up
      # Simulate having tried to reach a manage page before setup:
      get manage_shows_path
      follow_redirect! while response.redirect?

      complete_setup

      expect(response).to redirect_to(manage_shows_path)
    end
  end

  describe "the zero-org picker" do
    it "redirects a no-org user from the picker to producer setup" do
      sign_up
      get select_organization_path

      expect(response).to redirect_to(manage_producer_setup_path)
    end
  end
end
