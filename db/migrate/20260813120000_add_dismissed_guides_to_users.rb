# frozen_string_literal: true

class AddDismissedGuidesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :dismissed_guides, :jsonb, default: {}, null: false
  end
end
