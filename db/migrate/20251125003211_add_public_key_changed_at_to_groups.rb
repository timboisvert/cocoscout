# frozen_string_literal: true

class AddPublicKeyChangedAtToGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :groups, :public_key_changed_at, :datetime
  end
end
