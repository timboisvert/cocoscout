# frozen_string_literal: true

class MakeSocialsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Add polymorphic columns
    add_column :socials, :sociable_type, :string
    add_column :socials, :sociable_id, :integer

    # Backfill existing data
    execute <<-SQL
      UPDATE socials SET sociable_type = 'Person', sociable_id = person_id WHERE person_id IS NOT NULL
    SQL

    # Add index
    add_index :socials, %i[sociable_type sociable_id]

    # Remove old person_id column
    remove_column :socials, :person_id
  end

  def down
    # Add person_id column back
    add_column :socials, :person_id, :integer

    # Backfill data for Person types only
    execute <<-SQL
      UPDATE socials SET person_id = sociable_id WHERE sociable_type = 'Person'
    SQL

    # Remove polymorphic columns
    remove_index :socials, %i[sociable_type sociable_id]
    remove_column :socials, :sociable_type
    remove_column :socials, :sociable_id

    # Add foreign key back
    add_foreign_key :socials, :people
  end
end
