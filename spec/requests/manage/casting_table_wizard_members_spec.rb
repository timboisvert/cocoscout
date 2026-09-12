# frozen_string_literal: true

require "rails_helper"

# The Members step resolved talent pools by querying talent_pools.production_id,
# which only ever finds a production's OWN pool. A production borrowing another's
# shared pool, or an org in single-pool mode, therefore came up empty — and the
# talent-pool branch then stored nobody and sent you to Review, which bounced
# straight back to Members. Next looked like it did nothing.
RSpec.describe "Manage::CastingTableWizard members step", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let!(:production) { create(:production, organization: org, name: "Main Stage") }
  let!(:show) do
    create(:show, production: production, casting_enabled: true,
                  date_and_time: 3.weeks.from_now.change(hour: 20))
  end
  let(:performer) { create(:person, name: "Ada Actor") }

  before do
    org.people << performer
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  # Walk the wizard properly, so the session carries the state the members step
  # reads. Each context adds its own productions first, hence the explicit call.
  def walk_to_members!
    post manage_casting_tables_save_productions_path, params: { production_ids: [ production.id ] }
    post manage_casting_tables_save_events_path, params: { show_ids: [ show.id ] }
  end

  def use_talent_pool!
    post manage_casting_tables_save_members_path, params: { member_source: "talent_pool" }
  end

  context "when the production owns its talent pool" do
    before do
      production.talent_pool.talent_pool_memberships.create!(member: performer)
      walk_to_members!
    end

    it "moves on to review with the pool's members" do
      use_talent_pool!

      expect(response).to redirect_to(manage_casting_tables_review_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ada Actor")
    end
  end

  context "when the production borrows another production's pool" do
    let!(:other) { create(:production, organization: org, name: "Lender") }

    before do
      create(:talent_pool_share, talent_pool: other.talent_pool, production: production)
      other.talent_pool.talent_pool_memberships.create!(member: performer)
      walk_to_members!
    end

    it "finds the shared pool's members instead of dead-ending" do
      expect(production.effective_talent_pool).to eq(other.talent_pool)

      use_talent_pool!

      expect(response).to redirect_to(manage_casting_tables_review_path)
      follow_redirect!
      expect(response.body).to include("Ada Actor")
    end
  end

  context "when the org runs a single pool for everything" do
    let!(:hub) { create(:production, organization: org, name: "Hub") }

    before do
      org.update!(talent_pool_mode: :single, organization_talent_pool: hub.talent_pool)
      hub.talent_pool.talent_pool_memberships.create!(member: performer)
      walk_to_members!
    end

    it "finds the org pool's members" do
      expect(production.effective_talent_pool).to eq(hub.talent_pool)

      use_talent_pool!

      expect(response).to redirect_to(manage_casting_tables_review_path)
      follow_redirect!
      expect(response.body).to include("Ada Actor")
    end
  end

  context "when the pool really is empty" do
    before { walk_to_members! }

    it "says so instead of silently bouncing off the review step" do
      use_talent_pool!

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("nobody in the talent pool")
      expect(response.body).to include("Main Stage")
    end

    it "warns on the step itself, before Next is clicked" do
      get manage_casting_tables_members_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nobody's in the talent pool for Main Stage yet.")
    end
  end

  context "choosing members by hand" do
    before do
      production.talent_pool.talent_pool_memberships.create!(member: performer)
      walk_to_members!
    end

    it "offers the pool's people as checkboxes and remembers the choice" do
      get manage_casting_tables_members_path
      expect(response.body).to include("Ada Actor")

      post manage_casting_tables_save_members_path,
           params: { member_source: "manual", person_ids: [ performer.id ] }
      expect(response).to redirect_to(manage_casting_tables_review_path)

      # Coming back, the box is still ticked — the step used to read a wizard key
      # nothing ever wrote.
      get manage_casting_tables_members_path
      expect(response.body).to match(/value="#{performer.id}"[^>]*\n?[^>]*checked/)
    end
  end
end
