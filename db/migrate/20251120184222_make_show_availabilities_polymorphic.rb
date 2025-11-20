class MakeShowAvailabilitiesPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Add polymorphic columns
    add_column :show_availabilities, :available_entity_type, :string
    add_column :show_availabilities, :available_entity_id, :integer

    # Backfill existing data
    execute <<-SQL
      UPDATE show_availabilities SET available_entity_type = 'Person', available_entity_id = person_id WHERE person_id IS NOT NULL
    SQL

    # Add index
    add_index :show_availabilities, [ :available_entity_type, :available_entity_id ], name: 'index_show_availabilities_on_entity'

    # Update unique index - use the actual index name from the schema
    remove_index :show_availabilities, name: 'index_show_availabilities_on_person_id_and_show_id'
    add_index :show_availabilities, [ :available_entity_type, :available_entity_id, :show_id ], unique: true, name: 'index_show_availabilities_unique'

    # Remove old person_id column
    remove_column :show_availabilities, :person_id
  end

  def down
    # Add person_id column back
    add_column :show_availabilities, :person_id, :integer

    # Backfill data for Person types only
    execute <<-SQL
      UPDATE show_availabilities SET person_id = available_entity_id WHERE available_entity_type = 'Person'
    SQL

    # Remove new index and add back old one
    remove_index :show_availabilities, name: 'index_show_availabilities_unique'
    add_index :show_availabilities, [ :person_id, :show_id ], unique: true, name: 'index_show_availabilities_on_person_id_and_show_id'

    # Remove polymorphic columns
    remove_index :show_availabilities, name: 'index_show_availabilities_on_entity'
    remove_column :show_availabilities, :available_entity_type
    remove_column :show_availabilities, :available_entity_id

    # Add foreign key back
    add_foreign_key :show_availabilities, :people
  end
end
