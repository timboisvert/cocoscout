class ChangeShowCastingSourceNullable < ActiveRecord::Migration[8.1]
  def up
    # Make casting_source nullable so nil means "inherit from production"
    change_column_null :shows, :casting_source, true
    change_column_default :shows, :casting_source, nil

    # Set all existing shows to nil (inherit from production)
    Show.update_all(casting_source: nil)
  end

  def down
    # Reset to talent_pool default
    Show.where(casting_source: nil).update_all(casting_source: "talent_pool")
    change_column_default :shows, :casting_source, "talent_pool"
    change_column_null :shows, :casting_source, false
  end
end
