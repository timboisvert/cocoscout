# frozen_string_literal: true

class ConvertCastAssignmentStageToPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Remove old unique index first
    remove_index :cast_assignment_stages, name: 'index_cast_assignment_stages_unique', if_exists: true

    # Add polymorphic columns
    add_column :cast_assignment_stages, :assignable_type, :string
    add_column :cast_assignment_stages, :assignable_id, :integer

    # Migrate existing data
    CastAssignmentStage.reset_column_information
    CastAssignmentStage.where.not(person_id: nil).find_each do |stage|
      stage.update_columns(
        assignable_type: 'Person',
        assignable_id: stage.person_id
      )
    end

    # Remove old column
    remove_column :cast_assignment_stages, :person_id

    # Add new indexes
    add_index :cast_assignment_stages, %i[assignable_type assignable_id]
    add_index :cast_assignment_stages, %i[audition_cycle_id talent_pool_id assignable_type assignable_id],
              unique: true, name: 'index_cast_assignment_stages_unique'
  end

  def down
    # Remove new indexes
    remove_index :cast_assignment_stages, name: 'index_cast_assignment_stages_unique'
    remove_index :cast_assignment_stages, %i[assignable_type assignable_id]

    # Add back person_id column
    add_column :cast_assignment_stages, :person_id, :integer
    add_index :cast_assignment_stages, :person_id

    # Migrate data back (only Person types)
    CastAssignmentStage.reset_column_information
    CastAssignmentStage.where(assignable_type: 'Person').find_each do |stage|
      stage.update_columns(person_id: stage.assignable_id)
    end

    # Remove polymorphic columns
    remove_column :cast_assignment_stages, :assignable_type
    remove_column :cast_assignment_stages, :assignable_id

    # Restore old unique index
    add_index :cast_assignment_stages, %i[audition_cycle_id talent_pool_id person_id],
              unique: true, name: 'index_cast_assignment_stages_unique'
  end
end
