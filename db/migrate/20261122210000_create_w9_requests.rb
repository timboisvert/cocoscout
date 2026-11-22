# frozen_string_literal: true

# When an organization requested a W-9 from someone it pays who isn't on its
# staff (a performer, a contract person paid personally, an instructor), and
# when it last reminded them (Tim, 2026-11-22). Staff keep theirs on their
# staff record.
class CreateW9Requests < ActiveRecord::Migration[8.1]
  def change
    create_table :w9_requests do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.datetime :requested_at, null: false
      t.datetime :last_reminded_at
      t.timestamps
    end
    add_index :w9_requests, %i[organization_id person_id], unique: true
  end
end
