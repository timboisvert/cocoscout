class ChangeQuestionnaireAnswersValueToText < ActiveRecord::Migration[8.1]
  def change
    change_column :questionnaire_answers, :value, :text
  end
end
