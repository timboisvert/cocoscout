class CreateQuestionnaireAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :questionnaire_answers do |t|
      t.references :questionnaire_response, null: false, foreign_key: true
      t.references :question, null: false, foreign_key: true
      t.string :value

      t.timestamps
    end

    add_index :questionnaire_answers, [:questionnaire_response_id, :question_id], unique: true, name: 'index_q_answers_on_response_and_question'
  end
end
