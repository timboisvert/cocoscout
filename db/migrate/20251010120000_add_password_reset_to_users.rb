# frozen_string_literal: true

class AddPasswordResetToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :password_reset_token, :string unless column_exists?(:users, :password_reset_token)
    add_column :users, :password_reset_sent_at, :datetime unless column_exists?(:users, :password_reset_sent_at)
    add_index :users, :password_reset_token, unique: true unless index_exists?(:users, :password_reset_token)
  end
end
