# frozen_string_literal: true

class AddAvailabilityFieldsToQuestionnaires < ActiveRecord::Migration[8.1]
  def change
    add_column :questionnaires, :include_availability_section, :boolean, default: false, null: false
    add_column :questionnaires, :require_all_availability, :boolean, default: false, null: false
    add_column :questionnaires, :availability_event_types, :text
  end
end
