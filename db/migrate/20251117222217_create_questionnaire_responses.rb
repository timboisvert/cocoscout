class CreateQuestionnaireResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :questionnaire_responses do |t|
      t.references :questionnaire, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.timestamps
    end

    add_index :questionnaire_responses, [ :questionnaire_id, :person_id ], unique: true
  end
end
