# frozen_string_literal: true

class RenameHeaderTextAndRemoveSuccessText < ActiveRecord::Migration[8.1]
  def change
    # Rename header_text to instruction_text for ActionText rich texts
    # For Questionnaire records
    execute <<-SQL
      UPDATE action_text_rich_texts
      SET name = 'instruction_text'
      WHERE record_type = 'Questionnaire'
      AND name = 'header_text'
    SQL

    # For AuditionCycle records
    execute <<-SQL
      UPDATE action_text_rich_texts
      SET name = 'instruction_text'
      WHERE record_type = 'AuditionCycle'
      AND name = 'header_text'
    SQL

    # Remove success_text from Questionnaire records
    execute <<-SQL
      DELETE FROM action_text_rich_texts
      WHERE record_type = 'Questionnaire'
      AND name = 'success_text'
    SQL
  end
end
