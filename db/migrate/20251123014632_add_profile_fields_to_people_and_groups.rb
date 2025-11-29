class AddProfileFieldsToPeopleAndGroups < ActiveRecord::Migration[8.1]
  def change
    # Add JSONB column for profile visibility settings to people
    add_column :people, :profile_visibility_settings, :text, default: "{}"
    add_column :people, :hide_contact_info, :boolean, default: false, null: false

    # Add JSONB column for profile visibility settings to groups
    add_column :groups, :profile_visibility_settings, :text, default: "{}"
    add_column :groups, :hide_contact_info, :boolean, default: false, null: false
  end
end
