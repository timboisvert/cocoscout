class RemoveAvailabilityFromQuestionnaires < ActiveRecord::Migration[8.1]
  def change
    remove_column :questionnaires, :include_availability_section, :boolean, default: false
    remove_column :questionnaires, :require_all_availability, :boolean, default: false
    remove_column :questionnaires, :availability_show_ids, :text
  end
end
