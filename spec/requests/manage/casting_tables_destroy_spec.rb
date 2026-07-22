# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manage::CastingTables destroy (draft)", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production) }
  let!(:role) { create(:role, production: production) }
  let!(:person) { create(:person) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def draft_table
    CastingTable.create!(organization: org, name: "Spring Cast", status: "draft", created_by: owner)
  end

  it "deletes a draft table and discards its suggested (draft) assignments" do
    table = draft_table
    table.casting_table_draft_assignments.create!(show: show, role: role, assignable: person)

    expect {
      delete manage_casting_table_path(table)
    }.to change(CastingTable, :count).by(-1)
      .and change(CastingTableDraftAssignment, :count).by(-1)

    expect(response).to redirect_to(manage_casting_tables_path)
  end

  it "leaves real (finalized-elsewhere) assignments untouched" do
    table = draft_table
    table.casting_table_draft_assignments.create!(show: show, role: role, assignable: person)
    real = ShowPersonRoleAssignment.create!(show: show, role: role, assignable: person)

    delete manage_casting_table_path(table)

    expect(ShowPersonRoleAssignment.exists?(real.id)).to be(true)
  end

  it "refuses to delete a finalized table" do
    table = CastingTable.create!(organization: org, name: "Locked", status: "finalized", created_by: owner)

    expect {
      delete manage_casting_table_path(table)
    }.not_to change(CastingTable, :count)

    expect(response).to redirect_to(manage_casting_table_path(table))
  end
end
