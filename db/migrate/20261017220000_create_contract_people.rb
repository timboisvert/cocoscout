# frozen_string_literal: true

# Contract people (docs/contract_people_plan.md, Tim 2026-10-17): the people a
# contractor brings, with the contractor's visibility on My and nothing more.
# They are never production team members. An invitation by email carries the
# contract instead of a production.
class CreateContractPeople < ActiveRecord::Migration[8.1]
  def up
    create_table :contract_people do |t|
      t.references :contract, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :added_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :contract_people, %i[contract_id person_id], unique: true

    add_reference :team_invitations, :contract, foreign_key: true

    ContractPeopleTemplates.ensure!
  end

  def down
    remove_reference :team_invitations, :contract, foreign_key: true
    drop_table :contract_people
  end
end
