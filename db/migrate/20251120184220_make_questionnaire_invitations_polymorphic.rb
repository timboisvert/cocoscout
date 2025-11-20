class MakeQuestionnaireInvitationsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    # Add polymorphic columns
    add_column :questionnaire_invitations, :invitee_type, :string
    add_column :questionnaire_invitations, :invitee_id, :integer

    # Backfill existing data
    execute <<-SQL
      UPDATE questionnaire_invitations SET invitee_type = 'Person', invitee_id = person_id WHERE person_id IS NOT NULL
    SQL

    # Add index
    add_index :questionnaire_invitations, [:invitee_type, :invitee_id]
    
    # Update unique index - use the actual index name from the schema
    remove_index :questionnaire_invitations, name: 'index_q_invitations_on_questionnaire_and_person'
    add_index :questionnaire_invitations, [:invitee_type, :invitee_id, :questionnaire_id], unique: true, name: 'index_questionnaire_invitations_unique'

    # Remove old person_id column
    remove_column :questionnaire_invitations, :person_id
  end

  def down
    # Add person_id column back
    add_column :questionnaire_invitations, :person_id, :integer

    # Backfill data for Person types only
    execute <<-SQL
      UPDATE questionnaire_invitations SET person_id = invitee_id WHERE invitee_type = 'Person'
    SQL

    # Remove new index and add back old one
    remove_index :questionnaire_invitations, name: 'index_questionnaire_invitations_unique'
    add_index :questionnaire_invitations, [:questionnaire_id, :person_id], unique: true, name: 'index_q_invitations_on_questionnaire_and_person'

    # Remove polymorphic columns
    remove_index :questionnaire_invitations, [:invitee_type, :invitee_id]
    remove_column :questionnaire_invitations, :invitee_type
    remove_column :questionnaire_invitations, :invitee_id

    # Add foreign key back
    add_foreign_key :questionnaire_invitations, :people
  end
end
