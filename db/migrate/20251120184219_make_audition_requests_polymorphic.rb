class MakeAuditionRequestsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Add polymorphic columns
    add_column :audition_requests, :requestable_type, :string
    add_column :audition_requests, :requestable_id, :integer

    # Backfill existing data
    execute <<-SQL
      UPDATE audition_requests SET requestable_type = 'Person', requestable_id = person_id WHERE person_id IS NOT NULL
    SQL

    # Add index
    add_index :audition_requests, [ :requestable_type, :requestable_id ]

    # Remove old person_id column
    remove_column :audition_requests, :person_id
  end

  def down
    # Add person_id column back
    add_column :audition_requests, :person_id, :integer

    # Backfill data for Person types only
    execute <<-SQL
      UPDATE audition_requests SET person_id = requestable_id WHERE requestable_type = 'Person'
    SQL

    # Remove polymorphic columns
    remove_index :audition_requests, [ :requestable_type, :requestable_id ]
    remove_column :audition_requests, :requestable_type
    remove_column :audition_requests, :requestable_id

    # Add foreign key back
    add_foreign_key :audition_requests, :people
  end
end
