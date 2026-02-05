# frozen_string_literal: true

class UpdateExistingShowsEventType < ActiveRecord::Migration[8.0]
  def up
    # Update all existing shows that don't have an event_type set to "show"
    execute "UPDATE shows SET event_type = 'show' WHERE event_type IS NULL"
  end

  def down
    # No need to revert, we don't want to set them back to nil
  end
end
