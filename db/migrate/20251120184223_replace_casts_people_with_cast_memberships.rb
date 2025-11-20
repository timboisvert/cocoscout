class ReplaceCastsPeopleWithCastMemberships < ActiveRecord::Migration[8.1]
  def up
    # Create cast_memberships table
    create_table :cast_memberships do |t|
      t.references :cast, null: false, foreign_key: true
      t.string :castable_type, null: false
      t.integer :castable_id, null: false
      t.timestamps
    end

    # Add indexes
    add_index :cast_memberships, [:castable_type, :castable_id]
    add_index :cast_memberships, [:cast_id, :castable_type, :castable_id], unique: true, name: 'index_cast_memberships_unique'

    # Migrate data from casts_people to cast_memberships
    execute <<-SQL
      INSERT INTO cast_memberships (cast_id, castable_type, castable_id, created_at, updated_at)
      SELECT cast_id, 'Person', person_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM casts_people
    SQL

    # Drop the old join table
    drop_table :casts_people
  end

  def down
    # Create the old casts_people join table
    create_table :casts_people, id: false do |t|
      t.integer :cast_id
      t.integer :person_id
    end

    add_index :casts_people, :cast_id
    add_index :casts_people, :person_id

    # Migrate data back for Person types only
    execute <<-SQL
      INSERT INTO casts_people (cast_id, person_id)
      SELECT cast_id, castable_id
      FROM cast_memberships
      WHERE castable_type = 'Person'
    SQL

    # Drop cast_memberships table
    drop_table :cast_memberships
  end
end
