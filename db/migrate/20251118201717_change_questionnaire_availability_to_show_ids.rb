class ChangeQuestionnaireAvailabilityToShowIds < ActiveRecord::Migration[8.1]
  def change
    rename_column :questionnaires, :availability_event_types, :availability_show_ids
  end
end
