class CreateCastingTables < ActiveRecord::Migration[8.1]
  def change
    # Main casting table record
    create_table :casting_tables do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :status, null: false, default: "draft" # draft, finalized
      t.datetime :finalized_at
      t.references :finalized_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    # Join table for productions included in the casting table
    create_table :casting_table_productions do |t|
      t.references :casting_table, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.timestamps
    end
    add_index :casting_table_productions, [ :casting_table_id, :production_id ], unique: true, name: "idx_casting_table_productions_unique"

    # Join table for events/shows included in the casting table
    create_table :casting_table_events do |t|
      t.references :casting_table, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.timestamps
    end
    add_index :casting_table_events, [ :casting_table_id, :show_id ], unique: true, name: "idx_casting_table_events_unique"

    # Members included in the casting table (people/groups selected for casting)
    create_table :casting_table_members do |t|
      t.references :casting_table, null: false, foreign_key: true
      t.references :memberable, polymorphic: true, null: false
      t.timestamps
    end
    add_index :casting_table_members, [ :casting_table_id, :memberable_type, :memberable_id ], unique: true, name: "idx_casting_table_members_unique"

    # Draft assignments (not yet finalized)
    create_table :casting_table_draft_assignments do |t|
      t.references :casting_table, null: false, foreign_key: true
      t.references :show, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.references :assignable, polymorphic: true, null: false # Person or Group
      t.timestamps
    end
    add_index :casting_table_draft_assignments, [ :casting_table_id, :show_id, :role_id, :assignable_type, :assignable_id ], unique: true, name: "idx_casting_table_draft_assignments_unique"
  end
end
