# frozen_string_literal: true

class UpdateExistingAuditionCycleHeaderText < ActiveRecord::Migration[8.1]
  def up
    # Update any remaining AuditionCycle header_text records to instruction_text
    # (The previous migration should have handled this, but this ensures production data is updated)
    execute <<-SQL
      UPDATE action_text_rich_texts
      SET name = 'instruction_text'
      WHERE record_type = 'AuditionCycle'
      AND name = 'header_text'
    SQL
  end

  def down
    # Revert instruction_text back to header_text for AuditionCycle
    execute <<-SQL
      UPDATE action_text_rich_texts
      SET name = 'header_text'
      WHERE record_type = 'AuditionCycle'
      AND name = 'instruction_text'
    SQL
  end
end
