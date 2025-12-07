class AddPublicProfileToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :public_key, :string
    add_index :productions, :public_key, unique: true
    add_column :productions, :old_keys, :text
    add_column :productions, :public_key_changed_at, :datetime
    add_column :productions, :public_profile_enabled, :boolean, default: true
    add_column :productions, :event_visibility_overrides, :text
  end
end
