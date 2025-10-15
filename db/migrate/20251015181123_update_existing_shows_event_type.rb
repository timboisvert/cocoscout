class UpdateExistingShowsEventType < ActiveRecord::Migration[8.0]
  def up
    # Update all existing shows that don't have an event_type set to "show"
    Show.where(event_type: nil).update_all(event_type: "show")
  end

  def down
    # No need to revert, we don't want to set them back to nil
  end
end
