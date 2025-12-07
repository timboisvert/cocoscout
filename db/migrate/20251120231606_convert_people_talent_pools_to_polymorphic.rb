# frozen_string_literal: true

class ConvertPeopleTalentPoolsToPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Create the new polymorphic talent_pool_memberships table
    create_table :talent_pool_memberships do |t|
      t.references :talent_pool, null: false, foreign_key: true
      t.string :member_type, null: false
      t.integer :member_id, null: false
      t.timestamps
    end

    # Add indexes
    add_index :talent_pool_memberships, %i[member_type member_id]
    add_index :talent_pool_memberships, %i[talent_pool_id member_type member_id],
              unique: true, name: 'index_talent_pool_memberships_unique'

    # Migrate existing data from people_talent_pools to talent_pool_memberships
    # Only run if the old table exists
    return unless table_exists?(:people_talent_pools)

    execute <<-SQL
        INSERT INTO talent_pool_memberships (talent_pool_id, member_type, member_id, created_at, updated_at)
        SELECT talent_pool_id, 'Person', person_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM people_talent_pools
    SQL

    # Drop the old HABTM join table
    drop_table :people_talent_pools
  end

  def down
    # Recreate the old HABTM join table
    create_table :people_talent_pools, id: false do |t|
      t.integer :talent_pool_id, null: false
      t.integer :person_id, null: false
    end

    add_index :people_talent_pools, :talent_pool_id, name: 'index_people_talent_pools_on_talent_pool_id'
    add_index :people_talent_pools, :person_id

    # Migrate data back (only Person records)
    execute <<-SQL
      INSERT INTO people_talent_pools (talent_pool_id, person_id)
      SELECT talent_pool_id, member_id
      FROM talent_pool_memberships
      WHERE member_type = 'Person'
    SQL

    # Drop the polymorphic table
    drop_table :talent_pool_memberships
  end
end
