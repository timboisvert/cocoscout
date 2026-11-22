# frozen_string_literal: true

# A performer's or crew member's private access need (accessibility plan §3):
# for an audition (with its cycle) or for a production. Seen only by the
# production team managers, never in exports, and deleted when the audition
# cycle or the production ends (PurgeAccessRequestsJob).
class CreateAccessNeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :access_needs do |t|
      t.references :person, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.references :audition_cycle, foreign_key: true
      t.text :note, null: false
      t.timestamps
    end
    add_index :access_needs, %i[person_id audition_cycle_id], unique: true, where: "audition_cycle_id IS NOT NULL",
              name: "index_access_needs_one_per_audition"
    add_index :access_needs, %i[person_id production_id], unique: true, where: "audition_cycle_id IS NULL",
              name: "index_access_needs_one_per_production"
  end
end
