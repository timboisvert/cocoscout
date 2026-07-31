# frozen_string_literal: true

require "rails_helper"

# One course concept = one durable Production(type: course) with many runs
# (CourseOfferings). "Another run" must reuse the existing production, never spawn
# a new one, and keep each run's sessions isolated.
RSpec.describe "Course wizard: another run of an existing course", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let!(:course_production) { create(:production, organization: org, name: "Improv Bootcamp", production_type: :course) }
  let!(:run1) { create(:course_offering, production: course_production, title: "Improv Bootcamp — Spring", price_cents: 5000) }

  around do |example|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def cache_key = "course_offering_wizard:#{owner.id}:#{org.id}"

  it "adds a run to the existing production instead of creating a new one" do
    Rails.cache.write(cache_key, {
      title: "Improv Bootcamp — Fall",
      price_cents: 5500, currency: "usd", registration_mode: "custom", is_online: true,
      existing_course_production_id: course_production.id,
      session_rules: [ { type: "single", datetime: 2.months.from_now.change(hour: 18).iso8601, duration_minutes: 120 } ]
    }, expires_in: 1.hour)

    expect { post manage_course_wizard_create_path }.not_to change { Production.count }

    course_production.reload
    expect(course_production.course_offerings.count).to eq(2)
    run2 = course_production.course_offerings.order(:created_at).last
    expect(run2.title).to eq("Improv Bootcamp — Fall")
    # Sessions are isolated per run.
    expect(run2.sessions.count).to eq(1)
    expect(run1.sessions.count).to eq(0)
  end

  it "start step lists existing courses and prefills from the last run" do
    get manage_course_wizard_start_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Improv Bootcamp")

    post manage_course_wizard_start_path,
         params: { course_choice: "existing", existing_course_production_id: course_production.id }
    expect(response).to redirect_to(manage_course_wizard_basics_path)

    state = Rails.cache.read(cache_key).with_indifferent_access
    expect(state[:existing_course_production_id]).to eq(course_production.id)
    expect(state[:title]).to eq("Improv Bootcamp — Spring") # prefilled
    expect(state[:price_cents]).to eq(5000)
  end

  it "start step redirects to basics for a brand-new course choice" do
    post manage_course_wizard_start_path, params: { course_choice: "new" }
    expect(response).to redirect_to(manage_course_wizard_basics_path)
    expect(Rails.cache.read(cache_key).with_indifferent_access[:existing_course_production_id]).to be_nil
  end
end
