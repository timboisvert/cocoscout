# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/fixtures/migrations/20261118214309_crew_roles_become_plain_roles")

# Roles marked Crew before the Performing / Technical choice went become
# plain roles (Tim, 2026-11-18: "Yes, rewrite them"). Only the mark changes.
RSpec.describe CrewRolesBecomePlainRoles do
  let(:production) { create(:production) }
  let(:acts) { create(:production, casting_mode: "act_based") }

  def migrate!
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  it "makes every Crew role a plain role and leaves everything else about it alone" do
    crew = create(:role, production: production, name: "Stage Manager", quantity: 2, position: 3)
    crew.update_columns(category: "technical")
    show_role = create(:role, production: acts, name: "Stage Kitten", quantity: 2, standing: true)
    show_role.update_columns(category: "technical")
    cast = create(:show_person_role_assignment, show: create(:show, production: production), role: crew)
    host = create(:role, production: production, name: "Host")
    intermission = create(:role, production: acts, name: "Intermission", category: "break")

    migrate!

    expect(crew.reload).to have_attributes(category: "performing", name: "Stage Manager", quantity: 2, position: 3)
    expect(crew.show_person_role_assignments).to contain_exactly(cast)
    expect(show_role.reload).to have_attributes(category: "performing", quantity: 2, standing: true)
    expect(host.reload.category).to eq("performing")
    expect(intermission.reload.category).to eq("break")
    expect(Role.where(category: "technical")).to be_empty
  end
end
