# frozen_string_literal: true

require "rails_helper"

# Casting tables had no idea act-based shows existed. A cell held one role, so a
# person doing two acts in a night was half invisible; intermissions were
# castable and counted toward the denominator; two acts with the same name folded
# onto one slot; and the picker was a flat list of names with no running order,
# no sign of who else was in the show, and no conflict check.
RSpec.describe "Manage::CastingTables on act-based shows", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }

  let!(:production) do
    create(:production, organization: org, name: "Variety Hour", casting_mode: :act_based)
  end
  # A lineup with a repeated act name and an intermission — the shape that broke
  # every count.
  let!(:magic_one) { create(:role, production: production, name: "Magic", position: 1, quantity: 1) }
  let!(:variety)   { create(:role, production: production, name: "Variety", position: 2, quantity: 1) }
  let!(:interval)  { create(:role, production: production, name: "Intermission", position: 3, category: Role::BREAK_CATEGORY, quantity: 1) }
  let!(:magic_two) { create(:role, production: production, name: "Magic", position: 4, quantity: 1) }
  let!(:mc)        { create(:role, production: production, name: "MC", position: 5, quantity: 1, standing: true) }

  # Created after the lineup on purpose: an act-based show copies the
  # production's running order when it's created, so a show made first would
  # carry an empty one.
  let!(:show) do
    create(:show, production: production, casting_enabled: true,
                  date_and_time: 2.weeks.from_now.change(hour: 20), duration_minutes: 120)
  end

  let!(:ada) { create(:person, name: "Ada Actor") }
  let!(:bo)  { create(:person, name: "Bo Player") }

  let!(:table) { CastingTable.create!(organization: org, created_by: owner, name: "Autumn run", status: "draft") }

  before do
    org.people << ada
    org.people << bo
    table.casting_table_productions.create!(production: production)
    table.casting_table_events.create!(show: show)
    table.casting_table_members.create!(memberable: ada)
    table.casting_table_members.create!(memberable: bo)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def roles_for_show
    show.available_roles.order(:position).to_a
  end

  def role_named(name, ordinal: 1)
    roles_for_show.select { |r| r.name == name }[ordinal - 1]
  end

  def cell_params(member = ada)
    { show_id: show.id, assignable_type: member.class.name, assignable_id: member.id }
  end

  def open_cell(member = ada)
    get manage_casting_table_cell_path(table), params: cell_params(member)
    JSON.parse(response.body)["picker_html"].to_s
  end

  def assign!(role, member = ada, force: false)
    post manage_casting_table_assign_path(table),
         params: cell_params(member).merge(role_id: role.id, force: force), as: :json
  end

  describe "the cell panel" do
    it "names the acts in running order, numbered" do
      html = open_cell

      expect(html).to include("Running order")
      expect(html).to include("Magic").and include("Variety")
      # The numbers are what the flat list never had.
      expect(html).to match(/>\s*1\s*</).and match(/>\s*2\s*</)
    end

    it "shows intermissions as dividers, not something to cast" do
      html = open_cell

      expect(html).to include("Intermission")
      # A break gets no Add affordance and no capacity figure.
      expect(html).not_to match(/data-role-id="#{interval.id}"/)
    end

    it "keeps show roles in their own section" do
      expect(open_cell).to include("Show roles").and include("MC")
    end

    it "says who else is already in each slot" do
      assign!(role_named("Magic"), bo)

      html = open_cell(ada)

      expect(html).to include("Bo Player")
      expect(html).to include("Also in this show")
    end

    it "says what this member already holds" do
      assign!(role_named("Variety"), ada)

      html = open_cell(ada)

      expect(html).to include("Has")
      expect(html).to include("Act 2 · Variety")
    end
  end

  describe "casting" do
    it "lets one person hold two acts on the same night" do
      assign!(role_named("Magic", ordinal: 1))
      assign!(role_named("Magic", ordinal: 2))

      expect(response).to have_http_status(:ok)
      drafts = table.casting_table_draft_assignments.where(assignable: ada)
      expect(drafts.count).to eq(2)
      # Both acts, tracked separately — they used to fold onto one slot by name.
      expect(drafts.map(&:role_id)).to contain_exactly(role_named("Magic", ordinal: 1).id,
                                                       role_named("Magic", ordinal: 2).id)
    end

    it "renders the cell as the acts it holds, not just the first" do
      assign!(role_named("Magic", ordinal: 1))
      assign!(role_named("Magic", ordinal: 2))

      body = JSON.parse(response.body)
      expect(body["cell_html"]).to include("Acts 1, 3")
    end

    it "refuses to cast an intermission" do
      assign!(interval)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("intermission")
    end

    it "removes exactly the act you asked for" do
      first = role_named("Magic", ordinal: 1)
      second = role_named("Magic", ordinal: 2)
      assign!(first)
      assign!(second)

      delete manage_casting_table_unassign_path(table),
             params: cell_params.merge(role_id: second.id), as: :json

      expect(response).to have_http_status(:ok)
      expect(table.casting_table_draft_assignments.where(assignable: ada).map(&:role_id)).to eq([ first.id ])
    end

    it "won't take a role from another show's lineup" do
      other_show = create(:show, production: production, casting_enabled: true,
                                 date_and_time: 3.weeks.from_now.change(hour: 20))
      other_show.ensure_custom_running_order! if other_show.respond_to?(:ensure_custom_running_order!)
      foreign = other_show.available_roles.find { |r| !r.break? }

      if foreign && foreign.show_id.present?
        post manage_casting_table_assign_path(table),
             params: cell_params.merge(role_id: foreign.id), as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "counting" do
    it "renders the cells' click action as a real attribute, not page text" do
      get manage_casting_table_path(table)

      expect(response).to have_http_status(:ok)
      # An unquoted data-action containing ">" ended the tag early and printed
      # "casting-table#openRoleSelector>" into every cell.
      expect(response.body).to include('data-action="click-&gt;casting-table#openRoleSelector"')
      expect(response.body).not_to match(/data-action=click-/)
    end

    it "leaves intermissions out of the denominator" do
      get manage_casting_table_path(table)

      expect(response).to have_http_status(:ok)
      # Magic, Variety, Magic, MC — four castable slots, not five.
      expect(response.body).to include("0/4")
    end

    it "agrees with Show#fully_cast? once every castable slot is taken" do
      [ role_named("Magic", ordinal: 1), role_named("Variety"),
        role_named("Magic", ordinal: 2), role_named("MC") ].each_with_index do |role, i|
        assign!(role, i.even? ? ada : bo, force: true)
      end

      body = JSON.parse(response.body)
      expect(body["show_fully_cast"]).to be(true)
      expect(body["show_count"]).to eq(4)
      expect(body["show_total_slots"]).to eq(4)
    end
  end

  describe "conflicts" do
    it "asks before double-booking somebody busy elsewhere that night" do
      clash = create(:production, organization: org, name: "Other Room")
      clash_show = create(:show, production: clash, casting_enabled: true,
                                 date_and_time: show.date_and_time, duration_minutes: 120)
      clash_role = create(:role, production: clash, name: "Host", quantity: 1)
      clash_show.show_person_role_assignments.create!(role: clash_role, assignable: ada)

      assign!(role_named("Magic"))

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["conflicts"]).to be_present
    end

    it "goes ahead when told to" do
      clash = create(:production, organization: org, name: "Other Room")
      clash_show = create(:show, production: clash, casting_enabled: true,
                                 date_and_time: show.date_and_time, duration_minutes: 120)
      clash_role = create(:role, production: clash, name: "Host", quantity: 1)
      clash_show.show_person_role_assignments.create!(role: clash_role, assignable: ada)

      assign!(role_named("Magic"), ada, force: true)

      expect(response).to have_http_status(:ok)
      expect(table.casting_table_draft_assignments.where(assignable: ada).count).to eq(1)
    end

    it "doesn't treat a second act in the SAME show as a conflict" do
      assign!(role_named("Magic", ordinal: 1))
      assign!(role_named("Magic", ordinal: 2))

      expect(response).to have_http_status(:ok)
    end
  end

  describe "unfinalizing" do
    it "reopens the shows' casting" do
      assign!(role_named("Magic", ordinal: 1))
      assign!(role_named("Variety"), bo)
      assign!(role_named("Magic", ordinal: 2), bo, force: true)
      assign!(role_named("MC"), ada, force: true)

      post manage_casting_table_finalize_path(table)
      expect(show.reload.casting_finalized_at).to be_present

      post manage_casting_table_unfinalize_path(table)

      # This used to be guarded on a column that doesn't exist, so it never ran.
      expect(show.reload.casting_finalized_at).to be_nil
      expect(table.reload).to be_draft
    end
  end

  describe "the model guard" do
    it "refuses a break through any writer, not just the controller" do
      assignment = show.show_person_role_assignments.build(role: interval, assignable: ada)

      expect(assignment).not_to be_valid
      expect(assignment.errors[:role].join).to include("intermission")
    end
  end
end
