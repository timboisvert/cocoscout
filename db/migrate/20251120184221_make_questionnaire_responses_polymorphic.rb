class MakeQuestionnaireResponsesPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Add polymorphic columns
    add_column :questionnaire_responses, :respondent_type, :string
    add_column :questionnaire_responses, :respondent_id, :integer

    # Backfill existing data
    execute <<-SQL
      UPDATE questionnaire_responses SET respondent_type = 'Person', respondent_id = person_id WHERE person_id IS NOT NULL
    SQL

    # Add index
    add_index :questionnaire_responses, [:respondent_type, :respondent_id]
    
    # Update unique index - use the actual index name from the schema
    remove_index :questionnaire_responses, name: 'idx_on_questionnaire_id_person_id_14b49cba13'
    add_index :questionnaire_responses, [:respondent_type, :respondent_id, :questionnaire_id], unique: true, name: 'index_questionnaire_responses_unique'

    # Remove old person_id column
    remove_column :questionnaire_responses, :person_id
  end

  def down
    # Add person_id column back
    add_column :questionnaire_responses, :person_id, :integer

    # Backfill data for Person types only
    execute <<-SQL
      UPDATE questionnaire_responses SET person_id = respondent_id WHERE respondent_type = 'Person'
    SQL

    # Remove new index and add back old one
    remove_index :questionnaire_responses, name: 'index_questionnaire_responses_unique'
    add_index :questionnaire_responses, [:questionnaire_id, :person_id], unique: true, name: 'idx_on_questionnaire_id_person_id_14b49cba13'

    # Remove polymorphic columns
    remove_index :questionnaire_responses, [:respondent_type, :respondent_id]
    remove_column :questionnaire_responses, :respondent_type
    remove_column :questionnaire_responses, :respondent_id

    # Add foreign key back
    add_foreign_key :questionnaire_responses, :people
  end
end
