class MakeQuestionnairesProductionOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :questionnaires, :production_id, true
  end
end
