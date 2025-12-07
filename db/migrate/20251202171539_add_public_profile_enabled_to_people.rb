# frozen_string_literal: true

class AddPublicProfileEnabledToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :public_profile_enabled, :boolean, default: true, null: false
  end
end
