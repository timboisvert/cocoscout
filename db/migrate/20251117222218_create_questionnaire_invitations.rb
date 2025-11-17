class CreateQuestionnaireInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :questionnaire_invitations do |t|
      t.references :questionnaire, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.timestamps
    end

    add_index :questionnaire_invitations, [:questionnaire_id, :person_id], unique: true, name: 'index_q_invitations_on_questionnaire_and_person'
  end
end
