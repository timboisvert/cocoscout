# frozen_string_literal: true

class AddPublicKeyChangedAtToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :public_key_changed_at, :datetime
  end
end
