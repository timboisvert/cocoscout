# frozen_string_literal: true

class AddChangeTrackingToPerson < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :last_email_changed_at, :datetime
    add_column :people, :last_public_key_changed_at, :datetime
  end
end
