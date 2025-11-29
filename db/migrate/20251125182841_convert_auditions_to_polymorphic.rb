class ConvertAuditionsToPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Add polymorphic columns
    add_column :auditions, :auditionable_type, :string
    add_column :auditions, :auditionable_id, :integer

    # Migrate existing data
    Audition.reset_column_information
    Audition.find_each do |audition|
      audition.update_columns(
        auditionable_type: 'Person',
        auditionable_id: audition.person_id
      )
    end

    # Add index for polymorphic association
    add_index :auditions, [ :auditionable_type, :auditionable_id ], name: 'index_auditions_on_auditionable'

    # Remove old person_id column and index
    remove_index :auditions, :person_id
    remove_column :auditions, :person_id
  end

  def down
    # Add back person_id column
    add_column :auditions, :person_id, :integer
    add_index :auditions, :person_id

    # Migrate data back (only Person records)
    Audition.reset_column_information
    Audition.where(auditionable_type: 'Person').find_each do |audition|
      audition.update_columns(person_id: audition.auditionable_id)
    end

    # Remove polymorphic columns
    remove_index :auditions, name: 'index_auditions_on_auditionable'
    remove_column :auditions, :auditionable_type
    remove_column :auditions, :auditionable_id
  end
end
