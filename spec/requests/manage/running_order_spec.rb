# frozen_string_literal: true

require "rails_helper"

# The act-based casting board edits the show's running order in place:
# drag to reorder, add an act (typed, re-added from this show — duplicated
# with its performer — or pulled from the default lineup), add an
# intermission, and remove an act along with its assignments.
RSpec.describe "Manage::Casting running order", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:production) { create(:production, organization: org, casting_mode: "act_based") }

  let!(:magic)   { create(:role, production: production, name: "Magic", position: 0) }
  let!(:variety) { create(:role, production: production, name: "Variety", position: 1) }
  let!(:mc)      { create(:role, production: production, name: "MC", standing: true, position: 2) }

  let(:show) { create(:show, production: production) }
  let(:performer) { create(:person, name: "Trixie Tassels").tap { |p| org.people << p } }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def lineup_names
    show.custom_roles.reload.order(:position, :created_at).map(&:name)
  end

  describe "reorder" do
    it "reorders the acts and keeps show roles below, renumbering server-side" do
      copies = show.custom_roles.order(:position).to_a
      magic_copy, variety_copy = copies.reject(&:standing?)

      post manage_casting_show_running_order_reorder_path(production, show),
           params: { role_ids: [ variety_copy.id, magic_copy.id ] }

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Variety", "Magic", "MC" ])
      body = JSON.parse(response.body)
      # Numbers re-derive in the returned HTML: Variety is now Act 1
      expect(body["roles_html"]).to include('data-role-name="Act 1 · Variety"')
      expect(body["roles_html"]).to include('data-role-name="Act 2 · Magic"')
      expect(body["roles_config_html"]).to include("running order has been customized")
    end

    it "rejects an order that doesn't cover this show's acts" do
      post manage_casting_show_running_order_reorder_path(production, show),
           params: { role_ids: [ magic.id ] } # a production role id, not the show's copies

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for a role-based show" do
      role_based = create(:production, organization: org, casting_mode: "role_based")
      create(:role, production: role_based, name: "Host")
      other_show = create(:show, production: role_based)

      post manage_casting_show_running_order_reorder_path(role_based, other_show),
           params: { role_ids: [] }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "create (add act)" do
    it "adds a typed act at the end of the lineup, before show roles" do
      post manage_casting_show_running_order_acts_path(production, show),
           params: { kind: "act", name: "Juggling" }

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Magic", "Variety", "Juggling", "MC" ])
    end

    it "duplicates an act from this show, carrying its performer" do
      magic_copy = show.custom_roles.find_by(name: "Magic")
      create(:show_person_role_assignment, show: show, role: magic_copy, assignable: performer)

      post manage_casting_show_running_order_acts_path(production, show),
           params: { kind: "act", source_role_id: magic_copy.id }

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Magic", "Variety", "Magic", "MC" ])
      new_magic = show.custom_roles.where(name: "Magic").order(:position).last
      expect(new_magic.id).not_to eq(magic_copy.id)
      expect(show.show_person_role_assignments.where(role: new_magic).first.assignable).to eq(performer)
    end

    it "adds a default-lineup act uncast" do
      show.custom_roles.find_by(name: "Variety").destroy!

      post manage_casting_show_running_order_acts_path(production, show),
           params: { kind: "act", source_role_id: variety.id }

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Magic", "Variety", "MC" ])
      expect(show.show_person_role_assignments.count).to eq(0)
    end

    it "adds an intermission" do
      post manage_casting_show_running_order_acts_path(production, show),
           params: { kind: "break" }

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Magic", "Variety", "Intermission", "MC" ])
      expect(show.custom_roles.find_by(name: "Intermission").category).to eq("break")
    end

    it "adds a show role at the very end, with its quantity" do
      post manage_casting_show_running_order_acts_path(production, show),
           params: { kind: "show_role", name: "Stage Kitten", quantity: 2 }

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Magic", "Variety", "MC", "Stage Kitten" ])
      kitten = show.custom_roles.find_by(name: "Stage Kitten")
      expect(kitten).to be_standing
      expect(kitten.quantity).to eq(2)
    end

    it "materializes a legacy inheriting show on first edit, remapping assignments" do
      legacy = create(:show, production: production)
      legacy.custom_roles.destroy_all
      legacy.update_columns(use_custom_roles: false)
      assignment = create(:show_person_role_assignment, show: legacy, role: magic, assignable: performer)

      post manage_casting_show_running_order_acts_path(production, legacy),
           params: { kind: "act", name: "Juggling" }

      expect(response).to have_http_status(:ok)
      legacy.reload
      expect(legacy.use_custom_roles).to be(true)
      expect(assignment.reload.role.show_id).to eq(legacy.id)
      expect(assignment.role.name).to eq("Magic")
    end

    it "404s for another org's source role" do
      foreign_role = create(:role, name: "Foreign Act")

      post manage_casting_show_running_order_acts_path(production, show),
           params: { kind: "act", source_role_id: foreign_role.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "update (the pencil)" do
    it "renames an act" do
      magic_copy = show.custom_roles.find_by(name: "Magic")

      patch "/manage/casting/#{production.id}/#{show.id}/running_order/acts/#{magic_copy.id}",
            params: { name: "Grand Illusion" }

      expect(response).to have_http_status(:ok)
      expect(magic_copy.reload.name).to eq("Grand Illusion")
    end

    it "renames and resizes a show role" do
      mc_copy = show.custom_roles.find_by(name: "MC")

      patch "/manage/casting/#{production.id}/#{show.id}/running_order/acts/#{mc_copy.id}",
            params: { name: "Emcee", quantity: 2 }

      expect(response).to have_http_status(:ok)
      expect(mc_copy.reload.name).to eq("Emcee")
      expect(mc_copy.quantity).to eq(2)
    end

    it "refuses to shrink a show role below its cast" do
      mc_copy = show.custom_roles.find_by(name: "MC")
      mc_copy.update!(quantity: 2)
      create(:show_person_role_assignment, show: show, role: mc_copy, assignable: performer)
      other = create(:person).tap { |p| org.people << p }
      create(:show_person_role_assignment, show: show, role: mc_copy, assignable: other)

      patch "/manage/casting/#{production.id}/#{show.id}/running_order/acts/#{mc_copy.id}",
            params: { name: "MC", quantity: 1 }

      expect(response).to have_http_status(:unprocessable_content)
      expect(mc_copy.reload.quantity).to eq(2)
    end
  end

  describe "reset to default lineup" do
    before do
      # Customize: add an act the default doesn't have, cast people in both
      magic_copy = show.custom_roles.find_by(name: "Magic")
      create(:show_person_role_assignment, show: show, role: magic_copy, assignable: performer)
      extra = show.custom_roles.create!(name: "Juggling", production: production, position: 10)
      @juggler = create(:person, name: "Jolly Juggler").tap { |p| org.people << p }
      create(:show_person_role_assignment, show: show, role: extra, assignable: @juggler)
    end

    it "previews the new order, who migrates, and who gets wiped" do
      get manage_casting_show_running_order_reset_preview_path(production, show)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["new_lineup"].map { |e| e["name"] }).to eq([ "Magic", "Variety", "MC" ])
      expect(body["migrated"].map { |e| e["name"] }).to eq([ "Trixie Tassels" ])
      expect(body["migrated"].first["to"]).to eq("Magic (Act 1)")
      expect(body["wiped"].map { |e| e["name"] }).to eq([ "Jolly Juggler" ])
    end

    it "performs the reset, keeping same-named assignments and wiping the rest" do
      post manage_casting_show_running_order_reset_path(production, show)

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Magic", "Variety", "MC" ])
      remaining = show.show_person_role_assignments.reload
      expect(remaining.count).to eq(1)
      expect(remaining.first.assignable).to eq(performer)
      expect(remaining.first.role.name).to eq("Magic")
      expect(show.reload.running_order_matches_default?).to be(true)
    end
  end

  describe "destroy (remove act)" do
    it "asks for confirmation when the act is cast" do
      magic_copy = show.custom_roles.find_by(name: "Magic")
      create(:show_person_role_assignment, show: show, role: magic_copy, assignable: performer)

      delete manage_casting_show_running_order_act_path(production, show, magic_copy)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["needs_confirmation"]).to be(true)
      expect(body["assignment_names"]).to eq([ "Trixie Tassels" ])
      expect(show.custom_roles.reload.count).to eq(3)
    end

    it "removes the act and its assignments once confirmed" do
      magic_copy = show.custom_roles.find_by(name: "Magic")
      create(:show_person_role_assignment, show: show, role: magic_copy, assignable: performer)

      delete manage_casting_show_running_order_act_path(production, show, magic_copy, confirm: "true")

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Variety", "MC" ])
      expect(show.show_person_role_assignments.count).to eq(0)
    end

    it "removes an uncast act without ceremony" do
      variety_copy = show.custom_roles.find_by(name: "Variety")

      delete manage_casting_show_running_order_act_path(production, show, variety_copy)

      expect(response).to have_http_status(:ok)
      expect(lineup_names).to eq([ "Magic", "MC" ])
    end
  end

  describe "stale boards (rendered before the show owned its lineup)" do
    # A legacy show's board serves production role ids; its first mutation
    # materializes the copies — the posted ids must land on those copies.
    let(:legacy) do
      s = create(:show, production: production)
      s.custom_roles.destroy_all
      s.update_columns(use_custom_roles: false)
      s
    end

    def legacy_names
      legacy.custom_roles.reload.order(:position, :created_at).map(&:name)
    end

    it "removes an act posted by its production id, cast and all" do
      create(:show_person_role_assignment, show: legacy, role: magic, assignable: performer)

      delete manage_casting_show_running_order_act_path(production, legacy, magic, confirm: "true")

      expect(response).to have_http_status(:ok)
      expect(legacy.reload.use_custom_roles).to be(true)
      expect(legacy_names).to eq([ "Variety", "MC" ])
      expect(legacy.show_person_role_assignments.count).to eq(0)
      # The production's own lineup is untouched
      expect(production.roles.production_roles.count).to eq(3)
    end

    it "reorders using production ids" do
      post manage_casting_show_running_order_reorder_path(production, legacy),
           params: { role_ids: [ variety.id, magic.id ] }

      expect(response).to have_http_status(:ok)
      expect(legacy_names).to eq([ "Variety", "Magic", "MC" ])
    end

    it "renames via a production id without touching the default lineup" do
      patch "/manage/casting/#{production.id}/#{legacy.id}/running_order/acts/#{magic.id}",
            params: { name: "Grand Illusion" }

      expect(response).to have_http_status(:ok)
      expect(legacy_names).to include("Grand Illusion")
      expect(magic.reload.name).to eq("Magic")
    end

    it "duplicates an in-show act posted by its production id, carrying the cast" do
      create(:show_person_role_assignment, show: legacy, role: magic, assignable: performer)

      post manage_casting_show_running_order_acts_path(production, legacy),
           params: { kind: "act", source_role_id: magic.id }

      expect(response).to have_http_status(:ok)
      expect(legacy_names).to eq([ "Magic", "Variety", "Magic", "MC" ])
      expect(legacy.show_person_role_assignments.count).to eq(2)
      expect(legacy.show_person_role_assignments.map(&:assignable).uniq).to eq([ performer ])
    end

    it "still refuses a role that means nothing to this show" do
      foreign_show = create(:show, production: production)
      foreign_role = foreign_show.custom_roles.first

      delete manage_casting_show_running_order_act_path(production, legacy, foreign_role, confirm: "true")

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to include("reload the page")
    end
  end

  describe "act_options" do
    it "lists this show's acts (with performers) and missing default-lineup acts" do
      magic_copy = show.custom_roles.find_by(name: "Magic")
      create(:show_person_role_assignment, show: show, role: magic_copy, assignable: performer)
      show.custom_roles.find_by(name: "Variety").destroy!

      get manage_casting_show_running_order_act_options_path(production, show)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["in_show"].map { |o| o["name"] }).to eq([ "Magic" ])
      expect(body["in_show"].first["performers"]).to eq([ "Trixie Tassels" ])
      expect(body["in_show"].first["act_number"]).to eq(1)
      expect(body["from_default"].map { |o| o["name"] }).to eq([ "Variety" ])
    end

    it "suggests act names used before in this production, minus what's already offered" do
      other = create(:show, production: production) # copies Magic, Variety at creation
      other.custom_roles.create!(name: "Juggling", production: production, position: 20)
      other.custom_roles.create!(name: "Juggling", production: production, position: 21)

      get manage_casting_show_running_order_act_options_path(production, show)

      body = JSON.parse(response.body)
      names = body["frequent"].map { |o| o["name"] }
      expect(names).to include("Juggling")
      expect(body["frequent"].find { |o| o["name"] == "Juggling" }["count"]).to eq(2)
      # Already offered by the other sections, or a show role — not suggested again
      expect(names).not_to include("Magic")
      expect(names).not_to include("Variety")
      expect(names).not_to include("MC")
    end
  end
end
