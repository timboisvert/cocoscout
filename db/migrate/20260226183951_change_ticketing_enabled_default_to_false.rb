class ChangeTicketingEnabledDefaultToFalse < ActiveRecord::Migration[8.1]
  def up
    # Change default from true to false
    change_column_default :productions, :ticketing_enabled, false

    # Set all existing productions to false (opt-in required)
    Production.update_all(ticketing_enabled: false)
  end

  def down
    change_column_default :productions, :ticketing_enabled, true
  end
end
